module Api
  module V1
    module Accounts
      class RecurringExpensesController < Api::V1::Accounts::BaseController
        before_action :set_expense, only: [:show, :update, :destroy]

        def index
          authorize :recurring_expense, :index?
          expenses = Current.account.recurring_expenses
                            .includes(:financial_category, :bank_account)
                            .order(created_at: :desc)

          render json: expenses.map { |e| serialize(e) }
        end

        def show
          authorize :recurring_expense, :show?
          render json: serialize(@expense)
        end

        def create
          authorize :recurring_expense, :create?
          expense = Current.account.recurring_expenses.build(expense_params)
          expense.registered_by_id = Current.user.id

          if expense.save
            ::Financial::RecurringExpenseGenerator.new(expense).generate
            render json: serialize(expense.reload), status: :created
          else
            render json: { error: expense.errors.full_messages.join(', ') }, status: :unprocessable_entity
          end
        end

        def update
          authorize :recurring_expense, :update?
          if @expense.update(expense_params)
            render json: serialize(@expense)
          else
            render json: { error: @expense.errors.full_messages.join(', ') }, status: :unprocessable_entity
          end
        end

        def destroy
          authorize :recurring_expense, :destroy?
          @expense.update!(active: false)
          head :no_content
        end

        private

        def set_expense
          @expense = Current.account.recurring_expenses.find(params[:id])
        end

        def expense_params
          params.require(:recurring_expense).permit(
            :financial_category_id, :bank_account_id, :description,
            :amount, :payment_method, :frequency, :due_day,
            :competence_rule, :start_date, :end_date, :active,
            :auto_confirm, :notes
          )
        end

        def serialize(expense)
          {
            id:                    expense.id,
            description:           expense.description,
            amount:                expense.amount.to_f,
            frequency:             expense.frequency,
            due_day:               expense.due_day,
            competence_rule:       expense.competence_rule,
            payment_method:        expense.payment_method,
            start_date:            expense.start_date&.to_s,
            end_date:              expense.end_date&.to_s,
            last_generated_at:     expense.last_generated_at&.to_s,
            active:                expense.active,
            auto_confirm:          expense.auto_confirm,
            notes:                 expense.notes,
            financial_category_id: expense.financial_category_id,
            category_name:         expense.financial_category&.name,
            bank_account_id:       expense.bank_account_id,
            bank_account_name:     expense.bank_account&.name,
            created_at:            expense.created_at.iso8601
          }
        end
      end
    end
  end
end
