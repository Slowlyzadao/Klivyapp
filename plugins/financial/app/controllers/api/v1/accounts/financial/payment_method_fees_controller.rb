module Api
  module V1
    module Accounts
      module Financial
        # Taxas versionadas por meio de pagamento × quantidade de parcelas × vigência.
        # Canon `mapa-financeiro.json` step 3 — "NUNCA editar taxa existente.
        # Inativar antiga e criar nova com nova data de início."
        #
        # Por isso o endpoint `update` está intencionalmente AUSENTE — operador
        # só pode `create` (nova taxa com valid_from futuro) e `deactivate`
        # (cessa vigência da atual). UI deve mostrar essa restrição claramente.
        class PaymentMethodFeesController < BaseController
          skip_before_action :ensure_setup_complete!, only: %i[index]

          before_action :set_payment_method, only: %i[index create]
          before_action :set_fee, only: %i[show deactivate]
          before_action :authorize_write!, only: %i[create deactivate]

          def index
            fees = @payment_method.payment_method_fees
                                    .for_account(current_account.id)
                                    .alive
                                    .order(installments_count: :asc, valid_from: :desc)
            fees = fees.where(status: params[:status]) if params[:status].present?
            fees = fees.vigent_on(Date.parse(params[:vigent_on])) if params[:vigent_on].present?
            render json: { data: fees.map { |f| serialize(f) } }
          end

          def show
            render json: serialize(@fee)
          end

          # Cria nova taxa. Se já houver uma vigente pro mesmo
          # (installments_count, period), o exclusion constraint do banco
          # rejeita com `RecordNotUnique` (ou similar). UI deve orientar a
          # inativar antes via #deactivate.
          def create
            idempotent! do
              fee = @payment_method.payment_method_fees.new(
                fee_params.merge(account_id: current_account.id)
              )
              if fee.save
                render json: serialize(fee), status: :created
              else
                render json: { errors: fee.errors.full_messages }, status: :unprocessable_entity
              end
            rescue ActiveRecord::StatementInvalid => e
              # Pega o exclusion constraint violado (sobreposição de vigência)
              if e.message.include?('no_overlapping_payment_method_fees')
                render json: {
                  error: 'overlapping_fee_vigency',
                  message: 'Já existe taxa ativa para essa combinação de método+parcela+vigência. Inative a anterior antes de criar nova.'
                }, status: :unprocessable_entity
              else
                raise
              end
            end
          end

          # Inativa fee (cessa vigência). Substitui o `update` proibido.
          def deactivate
            idempotent_optional! do
              if @fee.status == 'inactive'
                return render(json: { ok: true, already_inactive: true })
              end

              @fee.deactivate!(on_date: parse_date(params[:on_date]), user: current_user)
              render json: serialize(@fee)
            end
          end

          private

          def set_payment_method
            @payment_method = ::Financial::PaymentMethod
                                .for_account(current_account.id)
                                .alive
                                .find(params[:payment_method_id])
          end

          def set_fee
            @fee = ::Financial::PaymentMethodFee
                     .for_account(current_account.id)
                     .alive
                     .find(params[:id])
          end

          def authorize_write!
            require_role!('ADMIN', 'GERENTE') and return unless user_has_any_role?(%w[ADMIN GERENTE])
          end

          def fee_params
            params.require(:payment_method_fee).permit(
              :installments_count, :fee_percent_basis_points, :fee_fixed_cents,
              :liquidation_days, :valid_from, :valid_to, :status
            ).tap do |p|
              # `payment_method_id` vem do nested route — força o do params da URL
              p[:payment_method_id] = @payment_method.id
            end
          end

          def parse_date(val)
            return Date.current if val.blank?

            Date.parse(val.to_s)
          rescue ArgumentError
            Date.current
          end

          def serialize(fee)
            {
              id: fee.id,
              payment_method_id: fee.payment_method_id,
              installments_count: fee.installments_count,
              fee_percent_basis_points: fee.fee_percent_basis_points,
              fee_percent: fee.fee_percent.to_s,
              fee_fixed_cents: fee.fee_fixed_cents,
              liquidation_days: fee.liquidation_days,
              valid_from: fee.valid_from,
              valid_to: fee.valid_to,
              status: fee.status,
              created_at: fee.created_at,
              updated_at: fee.updated_at
            }
          end
        end
      end
    end
  end
end
