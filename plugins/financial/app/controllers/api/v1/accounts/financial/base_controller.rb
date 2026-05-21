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
          rescue_from ::Financial::Gateways::GatewayError, with: :render_gateway_error
          rescue_from ActiveRecord::RecordNotFound, with: :render_not_found

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

          def setup_steps_state(state)
            {
              categories:        state.step_categories_done,
              bank_accounts:     state.step_bank_accounts_done,
              commission_rules:  state.step_commission_rules_done,
              recurring_expenses: state.step_recurring_expenses_done,
              revenue_goal:      state.step_revenue_goal_done
            }
          end

          # Mapeamento dos 5 perfis canon → klivy_role.preset_key.
          # Devolve true se o usuário corrente tem qualquer um dos roles passados.
          ROLE_PRESETS = {
            'RECEPCAO' => %w[recepcao recepcionista],
            'DENTIST'  => %w[dentista profissional],
            'GERENTE'  => %w[gerente coordenador],
            'ADMIN'    => %w[admin administrator dono],
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

          def render_gateway_error(err)
            render json: { error: 'gateway_error', message: err.message, code: err.code, payload: err.payload },
                   status: :bad_gateway
          end

          def render_not_found(err)
            render json: { error: 'not_found', message: err.message }, status: :not_found
          end
        end
      end
    end
  end
end
