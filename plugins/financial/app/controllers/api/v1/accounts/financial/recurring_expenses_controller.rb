module Api
  module V1
    module Accounts
      module Financial
        class RecurringExpensesController < BaseController
          skip_before_action :ensure_setup_complete!
          before_action :require_manager!
          before_action :set_recurring, only: %i[show update destroy]

          def index
            scope = ::Financial::RecurringExpense.for_account(current_account.id)
            scope = scope.active_recurring if params[:active] == 'true'
            render json: { data: scope.order(:name).map(&method(:serialize)) }
          end

          def show = render(json: serialize(@recurring))

          def create
            idempotent_optional! do
              rec = ::Financial::RecurringExpense.new(rec_params.merge(account_id: current_account.id))
              if rec.save
                render json: serialize(rec), status: :created
              else
                render json: { errors: rec.errors.full_messages }, status: :unprocessable_entity
              end
            end
          end

          def update
            if @recurring.update(rec_params)
              render json: serialize(@recurring)
            else
              render json: { errors: @recurring.errors.full_messages }, status: :unprocessable_entity
            end
          end

          def destroy
            @recurring.update!(active: false)  # canon §4.4: inativar não exclui despesas geradas
            render json: serialize(@recurring)
          end

          private

          def require_manager!
            render(json: { error: 'forbidden' }, status: :forbidden) unless user_has_any_role?(%w[GERENTE ADMIN])
          end

          def set_recurring
            @recurring = ::Financial::RecurringExpense.for_account(current_account.id).find(params[:id])
          end

          def rec_params
            params.require(:recurring_expense).permit(
              :name, :financial_dre_category_id, :financial_bank_account_id,
              :amount_cents, :variable_amount, :frequency, :due_day, :competence_rule,
              :start_date, :end_date, :auto_pay, :active
            )
          end

          def serialize(r)
            {
              id: r.id, name: r.name,
              category_id: r.financial_dre_category_id,
              bank_account_id: r.financial_bank_account_id,
              amount_cents: r.amount_cents,
              variable_amount: r.variable_amount,
              frequency: r.frequency, due_day: r.due_day,
              competence_rule: r.competence_rule,
              start_date: r.start_date, end_date: r.end_date,
              auto_pay: r.auto_pay, active: r.active
            }
          end
        end
      end
    end
  end
end
