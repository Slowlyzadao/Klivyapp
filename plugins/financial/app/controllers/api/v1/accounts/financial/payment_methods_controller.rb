module Api
  module V1
    module Accounts
      module Financial
        # Meios de pagamento configurados pela clínica.
        # Canon `mapa-financeiro.json` step 3.
        #
        # CRUD básico — a parte versionada (taxas) vive em
        # PaymentMethodFeesController. Aqui é só o "rótulo" do método
        # (Cielo Crédito, Pix Itaú, etc).
        class PaymentMethodsController < BaseController
          # Permite acessar mesmo se setup não estiver completo (é PARTE
          # do setup wizard — sem isso o usuário não consegue completar).
          # `update` está incluído porque ATIVAR um método pré-existente
          # inativo (status: inactive → active) é via PATCH e é exatamente
          # o que destrava o passo do wizard.
          # `simulate_fee` é read-only e usado pelo PaymentPlanWizardV2 —
          # precisa funcionar mesmo durante setup pra preview de taxas.
          skip_before_action :ensure_setup_complete!, only: %i[index create update simulate_fee]

          before_action :set_payment_method, only: %i[show update destroy simulate_fee]
          # `rename_provider` e `destroy_provider` também são escritas em massa
          # (alteram/inativam TODOS os métodos de um provedor) — devem exigir
          # ADMIN/GERENTE como o resto do CRUD. `rename_provider` estava sem gate
          # (auditoria 2026-05-30); `destroy_provider` chamava authorize_write!
          # inline — agora ambos via before_action (halt limpo, sem render duplo).
          before_action :authorize_write!, only: %i[create update destroy rename_provider destroy_provider]

          def index
            methods = ::Financial::PaymentMethod
                        .for_account(current_account.id)
                        .alive
                        .order(:kind, :name)
            methods = methods.where(kind: params[:kind]) if params[:kind].present?
            methods = methods.where(status: params[:status]) if params[:status].present?
            render json: { data: methods.map { |m| serialize(m) } }
          end

          def show
            render json: serialize(@payment_method)
          end

          def create
            idempotent! do
              method = ::Financial::PaymentMethod.new(
                payment_method_params.merge(account_id: current_account.id)
              )
              if method.save
                refresh_setup_state
                render json: serialize(method), status: :created
              else
                render json: { errors: method.errors.full_messages }, status: :unprocessable_entity
              end
            end
          end

          def update
            idempotent_optional! do
              if @payment_method.update(payment_method_params.except(:kind))
                # `kind` é frozen_attribute — qualquer tentativa de mudar
                # gera validation error automaticamente, mas excluímos do
                # permit pra retornar 422 limpo em vez de erro confuso.
                refresh_setup_state
                render json: serialize(@payment_method)
              else
                render json: { errors: @payment_method.errors.full_messages }, status: :unprocessable_entity
              end
            end
          end

          # Excluir provedor inteiro — soft-delete em massa de TODOS os
          # payment_methods do mesmo (account_id, provider). Útil pra
          # corrigir cadastro errado (operador digitou "Stnoe" em vez de
          # "Stone"). Bloqueia se QUALQUER método do grupo tiver fees ativos
          # ou foi usado (installments/expenses referenciam payment_method_id).
          #
          # Body: { provider: 'Stnoe' }
          def destroy_provider
            idempotent_optional! do
              raw_provider = params[:provider].to_s.strip
              if raw_provider.blank?
                return render(json: { error: 'provider_required' }, status: :unprocessable_entity)
              end

              scope = ::Financial::PaymentMethod
                        .for_account(current_account.id)
                        .alive
                        .where(provider: raw_provider)

              if scope.none?
                return render(json: { error: 'provider_not_found' }, status: :not_found)
              end

              # Guard: bloqueia se algum método foi USADO (lançamentos vinculados).
              # Verifica via existência de Installment apontando pra qualquer método
              # do grupo. Expense não tem FK pra payment_method (usa enum string),
              # então não entra na checagem.
              method_ids = scope.pluck(:id)
              used_ids = []
              if defined?(::Financial::Installment)
                used_ids |= ::Financial::Installment.where(payment_method_id: method_ids).distinct.pluck(:payment_method_id)
              end

              if used_ids.any?
                used_names = ::Financial::PaymentMethod.where(id: used_ids).pluck(:name).join(', ')
                return render(json: {
                  error: 'provider_in_use',
                  message: "Não dá pra excluir o provedor — método(s) já usado(s) em lançamentos: #{used_names}. Inative individualmente ou migre os lançamentos antes."
                }, status: :unprocessable_entity)
              end

              # Tudo limpo — soft-delete em todos os métodos do grupo (+ fees ativos).
              # `dependent: :restrict_with_error` em payment_method_fees protegeria,
              # mas como nada foi usado, não há fees consumidas → seguro inativar.
              now = Time.current
              ActiveRecord::Base.transaction do
                scope.find_each do |pm|
                  pm.payment_method_fees.alive.update_all(deleted_at: now, deleted_by_id: current_user&.id)
                  pm.soft_delete!(user: current_user)
                end
              end

              ::Financial::SetupState.for_account(current_account.id).refresh! rescue nil
              render json: { ok: true, deleted_count: method_ids.size, provider: raw_provider }
            end
          end

          # Rename de provedor — propaga `provider_alias` em TODOS os
          # payment_methods do mesmo (account_id, provider). Operador edita
          # o nome do grupo na UI e todos os métodos sob aquele provedor
          # passam a exibir o apelido. Provider raw (e portanto o agrupamento)
          # permanece intacto — alias é só display.
          #
          # Body: { provider: 'Cielo', provider_alias: 'Cielo - Loja Centro' }
          # provider_alias vazio/null limpa o alias (volta a mostrar raw).
          def rename_provider
            idempotent_optional! do
              raw_provider = params[:provider].to_s.strip
              new_alias = params[:provider_alias].to_s.strip.presence

              if raw_provider.blank?
                return render(json: { error: 'provider_required' }, status: :unprocessable_entity)
              end

              scope = ::Financial::PaymentMethod
                        .for_account(current_account.id)
                        .alive
                        .where(provider: raw_provider)

              if scope.none?
                return render(json: { error: 'provider_not_found' }, status: :not_found)
              end

              updated = scope.update_all(provider_alias: new_alias, updated_at: Time.current)
              render json: { ok: true, updated_count: updated, provider: raw_provider, provider_alias: new_alias }
            end
          end

          # DELETE = soft-delete (canon: nunca deleta de verdade).
          # Permitido SE o método nunca foi usado em lançamentos. Cadeia de guards:
          #   1. Tem Installment vinculada? → bloqueia (lançamento já registrado)
          #   2. Tem fees ativos? → inativa fees junto (não bloqueia, é parte da limpeza)
          # UX: operador erra cadastro e quer remover; só não pode se já recebeu
          # algo por esse método (pra preservar histórico contábil).
          def destroy
            idempotent_optional! do
              if defined?(::Financial::Installment) && ::Financial::Installment.where(payment_method_id: @payment_method.id).exists?
                return render(json: {
                  error: 'method_in_use',
                  message: 'Este método já foi usado em lançamentos (recebimentos). Inative em vez de excluir — assim o histórico fica preservado.'
                }, status: :unprocessable_entity)
              end

              ActiveRecord::Base.transaction do
                @payment_method.payment_method_fees.alive.update_all(deleted_at: Time.current, deleted_by_id: current_user&.id)
                @payment_method.soft_delete!(user: current_user)
              end
              refresh_setup_state
              render json: { ok: true }
            end
          end

          # GET /financial/v2/payment_methods/:id/simulate_fee
          #
          # Preview da taxa vigente pra este método em (amount × installments_count × on_date).
          # Read-only — não persiste nada, não dispara AuditLog. Usado pelo
          # PaymentPlanWizardV2 (frontend) pra mostrar bruto × taxa × líquido
          # antes do operador confirmar.
          #
          # Query params:
          #   amount_cents       (required, integer > 0) — interpretação depende de `mode`
          #   installments_count (optional, default 1; 1..24)
          #   on_date            (optional, default Date.current; ISO 'YYYY-MM-DD')
          #   mode               (optional, default 'absorb') — 'absorb' (V2 canon: clínica
          #                       absorve MDR, amount_cents é o que paciente paga) ou
          #                       'passthrough' (F2.5: cliente paga MDR, amount_cents é
          #                       o BASE que clínica recebe). Quando ausente, usa o flag
          #                       `passes_fee_to_patient` do método pra escolher.
          #
          # Respostas:
          #   200 — taxa resolvida (fee_resolved: true) ou sem fee cadastrada (fee_resolved: false, valores zerados)
          #   422 — amount_cents ausente/inválido ou installments_count fora do range
          def simulate_fee
            amount_cents = params[:amount_cents].to_i
            installments_count = (params[:installments_count] || 1).to_i
            on_date = parse_simulate_date(params[:on_date]) || Date.current
            mode = resolve_simulation_mode(params[:mode], @payment_method.passes_fee_to_patient)

            if amount_cents <= 0
              return render(json: { error: 'amount_cents_required', message: 'amount_cents deve ser inteiro > 0' }, status: :unprocessable_entity)
            end

            if installments_count < 1 || installments_count > 24
              return render(json: { error: 'invalid_installments_count', message: 'installments_count deve estar entre 1 e 24' }, status: :unprocessable_entity)
            end

            fee = @payment_method.fee_for(installments_count: installments_count, on_date: on_date)

            # Dois cálculos diferentes conforme o modelo:
            # - absorb: amount_cents é o que paciente paga; fee retida; clínica recebe net = amount - fee
            # - passthrough: amount_cents é o BASE (clínica recebe); paciente paga base inflado pra cobrir o MDR
            if mode == 'passthrough' && fee
              amount_for_patient_cents = fee.inflate_amount_cents(amount_cents)
              fee_amount_cents = amount_for_patient_cents - amount_cents
              net_amount_cents = amount_cents
              base_amount_cents = amount_cents
            else
              fee_amount_cents = fee ? fee.calculate_fee_cents(amount_cents) : 0
              net_amount_cents = amount_cents - fee_amount_cents
              amount_for_patient_cents = amount_cents
              base_amount_cents = net_amount_cents
            end

            render json: {
              data: {
                payment_method_id: @payment_method.id,
                payment_method_kind: @payment_method.kind,
                payment_method_name: @payment_method.name,
                passes_fee_to_patient: @payment_method.passes_fee_to_patient,
                mode: mode,
                amount_cents: amount_cents,               # input do operador
                amount_for_patient_cents: amount_for_patient_cents, # quanto paciente paga
                base_amount_cents: base_amount_cents,     # quanto entra como receita da clínica
                installments_count: installments_count,
                on_date: on_date,
                fee_resolved: !fee.nil?,
                fee_id: fee&.id,
                fee_percent_basis_points: fee&.fee_percent_basis_points.to_i,
                fee_fixed_cents: fee&.fee_fixed_cents.to_i,
                fee_amount_cents: fee_amount_cents,
                net_amount_cents: net_amount_cents,       # quanto cai na conta da clínica
                liquidation_days: fee&.liquidation_days.to_i,
                expected_liquidation_date: on_date + fee&.liquidation_days.to_i.days
              }
            }
          end

          private

          def parse_simulate_date(value)
            return nil if value.blank?
            Date.parse(value.to_s)
          rescue ArgumentError, TypeError
            nil
          end

          # Resolve qual modelo de cálculo aplicar:
          # - param explícito 'absorb' ou 'passthrough' vence
          # - sem param: usa flag do método (`passes_fee_to_patient` → 'passthrough', senão 'absorb')
          # Wizard passa explicitamente; smoke tests/curl podem omitir.
          def resolve_simulation_mode(raw_mode, passes_default)
            mode = raw_mode.to_s.downcase
            return mode if %w[absorb passthrough].include?(mode)
            passes_default ? 'passthrough' : 'absorb'
          end

          def set_payment_method
            @payment_method = ::Financial::PaymentMethod
                                .for_account(current_account.id)
                                .alive
                                .find(params[:id])
          end

          def authorize_write!
            require_role!('ADMIN', 'GERENTE') and return unless user_has_any_role?(%w[ADMIN GERENTE])
          end

          def payment_method_params
            params.require(:payment_method).permit(
              :kind, :name, :provider, :provider_alias, :default_bank_account_id,
              :supports_installments, :max_installments, :status,
              # F2.5 — modelo de repasse de MDR ao paciente. Quando true,
              # `ApproveBudget` infla o amount_cents das parcelas vinculadas
              # para que a clínica receba o valor base cheio.
              :passes_fee_to_patient,
              # Política de baixa (2026-05-27): manual | on_confirm | on_due_date.
              # Guardrail no model: on_due_date só p/ crédito/débito.
              :settlement_mode
            )
          end

          def serialize(method)
            {
              id: method.id,
              kind: method.kind,
              name: method.name,
              provider: method.provider,
              provider_alias: method.provider_alias,
              display_provider: method.display_provider,
              default_bank_account_id: method.default_bank_account_id,
              supports_installments: method.supports_installments,
              max_installments: method.max_installments,
              status: method.status,
              passes_fee_to_patient: method.passes_fee_to_patient,
              settlement_mode: method.settlement_mode,
              active_fees_count: method.payment_method_fees.alive.where(status: 'active').count,
              created_at: method.created_at,
              updated_at: method.updated_at
            }
          end

          # `refresh!` recalcula TODOS os steps a partir de queries reais
          # do banco — idempotente e robusto contra dessincronia. Chamado
          # tanto em create quanto em update porque ativar/inativar um
          # método existente também afeta `step_payment_methods_done`.
          def refresh_setup_state
            ::Financial::SetupState.for_account(current_account.id).refresh!
          rescue StandardError => e
            Rails.logger.warn "[PaymentMethods] refresh_setup_state failed: #{e.message}"
          end
        end
      end
    end
  end
end
