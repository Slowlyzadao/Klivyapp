module Api
  module V1
    module Accounts
      module Financial
        class PatientCreditsController < BaseController
          # GET /financial/v2/patient_credits?patient_id=...
          def index
            scope = ::Financial::PatientCredit.for_account(current_account.id)
            scope = scope.for_patient(params[:patient_id]) if params[:patient_id].present?
            scope = scope.order(occurred_at: :desc)
            render json: {
              balance_cents: scope.sum(:amount_cents),
              data: scope.limit(100).map(&method(:serialize))
            }
          end

          def create
            require_role!('GERENTE', 'ADMIN') and return unless user_has_any_role?(%w[GERENTE ADMIN])

            idempotent! do
              credit = ::Financial::PatientCredit.new(credit_params.merge(
                account_id: current_account.id,
                registered_by_id: current_user.id,
                occurred_at: Time.current,
                origin: 'ajuste_manual'
              ))
              if credit.save
                render json: serialize(credit), status: :created
              else
                render json: { errors: credit.errors.full_messages }, status: :unprocessable_entity
              end
            end
          end

          private

          def credit_params
            params.require(:patient_credit).permit(:patient_id, :amount_cents, :description)
          end

          def serialize(c)
            {
              id: c.id, patient_id: c.patient_id, amount_cents: c.amount_cents,
              origin: c.origin, origin_type: c.origin_type, origin_id: c.origin_id,
              description: c.description, occurred_at: c.occurred_at
            }
          end
        end
      end
    end
  end
end
