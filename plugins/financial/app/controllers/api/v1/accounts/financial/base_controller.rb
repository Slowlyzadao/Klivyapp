# Garantir que Financial::Gateways esteja carregado antes da classe ser parseada
# (rescue_from abaixo referencia ::Financial::Gateways::GatewayError em tempo de
# class load, e lib/ do plugin não é autoload do Zeitwerk).
require Rails.root.join('plugins/financial/lib/financial.rb')

module Api
  module V1
    module Accounts
      module Financial
        # Base controller para o novo módulo financeiro v2 (namespace Financial).
        # Convenção:
        # - todos os endpoints exigem autenticação (herdada do parent)
        # - Idempotência server-side disponível via include
        # - Permissões via BeclinicPermissible (RBAC Klivy é o único — memory)
        # - Account scoping via Current.account
        class BaseController < ::Api::V1::Accounts::BaseController
          include ::Financial::IdempotentAction

          before_action :ensure_setup_complete!, except: %i[setup_state setup_complete_step]
          rescue_from ::Financial::Gateways::GatewayError,        with: :render_gateway_error
          rescue_from ActiveRecord::RecordNotFound,                with: :render_not_found
          rescue_from ::Financial::Errors::PeriodClosed,           with: :render_period_closed
          rescue_from ::Financial::Errors::TenantMismatch,         with: :render_forbidden
          rescue_from ::Financial::Errors::FrozenAttributeError,   with: :render_unprocessable
          rescue_from ::Financial::Errors::IdempotencyMismatch,    with: :render_unprocessable
          rescue_from ::Financial::Errors::OverPayment,            with: :render_unprocessable
          rescue_from ::Financial::Errors::InsufficientBalance,    with: :render_unprocessable
          rescue_from ::Financial::Errors::InvariantViolation,     with: :render_unprocessable
          rescue_from ::Financial::Errors::SetupIncomplete,        with: :render_precondition_failed

          private

          def current_user_or_actor
            ::Current.try(:user) || @user || @resource
          end

          # NÃO sobrescrever current_account — o método herdado de
          # EnsureCurrentAccountHelper busca o Account no DB, valida acesso e
          # seta @current_account + Current.account. Sobrescrever quebra a chain
          # do before_action :current_account do parent (vira no-op),
          # deixando @current_account = nil → qualquer `.id` explode.

          # F-04: bloqueia uso até wizard de setup estar completo (passos obrigatórios).
          # Retorna 412 Precondition Failed com instrução clara para o frontend exibir wizard.
          def ensure_setup_complete!
            return unless ::Financial::SetupState  # safe-guard se modelo não carregado

            state = ::Financial::SetupState.for_account(current_account.id)
            return if state.required_steps_done?

            render json: {
              error: 'financial_setup_required',
              message: 'O módulo financeiro requer configuração inicial. Conclua o wizard antes de prosseguir.',
              progress_percent: state.progress_percent,
              steps: setup_steps_state(state)
            }, status: :precondition_failed
          end

          # Reflete os passos OBRIGATÓRIOS — os que de fato bloqueiam o módulo
          # via required_steps_done?. Versão anterior listava passos OPCIONAIS e
          # OMITIA payment_methods, mascarando "Formas de Pagamento" como causa
          # do 412 (qualquer UI que itemizasse esse `steps` enganaria o usuário).
          def setup_steps_state(state)
            {
              categories:      state.step_categories_done,
              bank_accounts:   state.step_bank_accounts_done,
              payment_methods: state.step_payment_methods_done
            }
          end

          # Mapeamento dos 5 perfis canon → klivy_role.preset_key.
          # Devolve true se o usuário corrente tem qualquer um dos roles passados.
          ROLE_PRESETS = {
            'RECEPCAO' => %w[recepcao recepcionista],
            'DENTIST'  => %w[dentista profissional],
            'GERENTE'  => %w[gerente coordenador],
            'ADMIN'    => %w[admin administrator], # 'dono' removido (canon RBAC 2026-04-30; sem preset_key dono)
            'AUDITOR'  => %w[auditor contador]
          }.freeze

          def require_role!(*roles)
            return if user_has_any_role?(roles)

            ::Financial::AuditLog.async_record(
              ::Financial::AuditLog.new(account_id: current_account.id, id: 0, entity_type: 'permission', entity_id: 0),
              action: 'denied',
              before: { required_roles: roles },
              after: { user_id: current_user.id, path: request.fullpath }
            )
            render json: { error: 'forbidden', required_roles: roles }, status: :forbidden
          end

          def user_has_any_role?(roles)
            return true if super_admin?
            return false unless current_user.respond_to?(:account_users)

            account_user = current_user.account_users.find_by(account_id: current_account.id)
            return false unless account_user
            # Mapeamento: administrator role do account_user é sempre ADMIN.
            return true if account_user.try(:administrator?) && roles.include?('ADMIN')

            preset = account_user.try(:klivy_role)&.preset_key.to_s.downcase
            return false if preset.blank?

            roles.flat_map { |r| ROLE_PRESETS[r.to_s] || [r.to_s.downcase] }.include?(preset)
          end

          def super_admin?
            current_user.try(:super_admin?) || false
          end

          # Gate de leitura do FINANCEIRO DO PACIENTE (aba do prontuário).
          #
          # Fonte de verdade única: RBAC Klivy `patients.view_financial` — a
          # MESMA permission que o frontend usa pra renderizar a aba
          # (`Record.vue`). NÃO usar `financial.*` aqui: essas perms gateiam o
          # módulo financeiro standalone (sidebar/dashboard), não o financeiro
          # de UM paciente. Ex.: Recepção e SDR têm `financial.view_dashboard`
          # mas NÃO `patients.view_financial`, logo não devem ler o financeiro
          # de um paciente específico. `beclinic_can?` já dá bypass total pra
          # super_admin e administrator nativo da conta.
          #
          # Usado SÓ pelos endpoints exclusivos da aba (PatientSummaries/
          # PatientTimelines) via `before_action`. Endpoints compartilhados com
          # o módulo standalone (installments/budgets) mantêm sua própria
          # autorização — não herdam este gate.
          def ensure_view_patient_financial!
            return if current_user&.beclinic_can?(current_account, :patients, :view_financial)

            render json: {
              error: 'forbidden',
              message: 'Você não tem permissão para ver o financeiro do paciente.'
            }, status: :forbidden
          end

          def render_gateway_error(err)
            render json: { error: 'gateway_error', message: err.message, code: err.code, payload: err.payload },
                   status: :bad_gateway
          end

          def render_not_found(err)
            render json: { error: 'not_found', message: err.message }, status: :not_found
          end

          # 423 Locked — período contábil fechado (Financial::PeriodClosure ativo).
          def render_period_closed(err)
            render json: {
              error: 'period_closed',
              message: err.message,
              period_date: err.try(:period_date)
            }, status: :locked
          end

          # 403 Forbidden — TenantMismatch (bug — não deve ocorrer em código sadio).
          def render_forbidden(_err)
            render json: { error: 'forbidden' }, status: :forbidden
          end

          # 422 — violações de invariante (over-payment, frozen, etc).
          def render_unprocessable(err)
            render json: {
              error: err.class.name.demodulize.underscore,
              message: err.message
            }, status: :unprocessable_entity
          end

          # 412 — setup incompleto (também é o que ensure_setup_complete! retorna).
          def render_precondition_failed(err)
            render json: {
              error: 'financial_setup_required',
              message: err.message
            }, status: :precondition_failed
          end
        end
      end
    end
  end
end
