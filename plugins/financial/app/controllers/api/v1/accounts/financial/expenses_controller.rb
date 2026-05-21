module Api
  module V1
    module Accounts
      module Financial
        class ExpensesController < BaseController
          before_action :set_expense, only: %i[show update destroy pay reverse]

          def index
            scope = ::Financial::Expense.for_account(current_account.id)
            scope = scope.where(status: params[:status]) if params[:status].present?
            scope = scope.where(financial_dre_category_id: params[:category_id]) if params[:category_id].present?
            scope = scope.where(financial_bank_account_id: params[:bank_account_id]) if params[:bank_account_id].present?
            scope = scope.where('due_date >= ?', params[:from]) if params[:from].present?
            scope = scope.where('due_date <= ?', params[:to]) if params[:to].present?
            scope = scope.where('LOWER(description) LIKE ?', "%#{params[:q].downcase}%") if params[:q].present?
            scope = scope.where('due_date < ?', Date.current) if params[:overdue_only] == 'true'

            sort = params[:sort] || 'due_date'
            direction = params[:direction] == 'desc' ? :desc : :asc
            scope = scope.order(sort => direction)

            render json: { data: scope.limit(100).map { |e| serialize(e) }, meta: meta_for(scope) }
          end

          def show = render(json: serialize(@expense))

          def create
            require_role!('RECEPCAO', 'GERENTE', 'ADMIN') and return unless user_has_any_role?(%w[RECEPCAO GERENTE ADMIN])

            idempotent! do
              expense = ::Financial::Expense.new(expense_params.merge(account_id: current_account.id, registered_by_id: current_user.id))
              if expense.save
                render json: serialize(expense), status: :created
              else
                render json: { errors: expense.errors.full_messages }, status: :unprocessable_entity
              end
            end
          end

          def update
            require_role!('GERENTE', 'ADMIN') and return unless user_has_any_role?(%w[GERENTE ADMIN])

            return render(json: { error: 'despesa paga não pode ser editada' }, status: :unprocessable_entity) if @expense.status == 'pago'
            if @expense.update(expense_params)
              render json: serialize(@expense)
            else
              render json: { errors: @expense.errors.full_messages }, status: :unprocessable_entity
            end
          end

          def destroy
            require_role!('GERENTE', 'ADMIN') and return unless user_has_any_role?(%w[GERENTE ADMIN])
            return render(json: { error: 'despesa paga não pode ser excluída' }, status: :unprocessable_entity) if @expense.status == 'pago'

            @expense.soft_delete!(user: current_user)
            head :no_content
          end

          # POST /financial/v2/expenses/:id/pay
          def pay
            require_role!('RECEPCAO', 'GERENTE', 'ADMIN') and return unless user_has_any_role?(%w[RECEPCAO GERENTE ADMIN])

            idempotent! do
              bank = ::Financial::BankAccount.for_account(current_account.id).find(params[:bank_account_id])
              result = ::Financial::PayExpense.call(
                expense: @expense, actor: current_user, bank_account: bank,
                amount_cents: params[:amount_cents]&.to_i,
                paid_at: params[:paid_at],
                payment_method: params[:payment_method],
                notes: params[:notes]
              )
              if result.success?
                render json: serialize(result[:expense]), status: :ok
              else
                render json: { errors: result.errors }, status: :unprocessable_entity
              end
            end
          end

          # POST /financial/v2/expenses/:id/reverse
          def reverse
            require_role!('GERENTE', 'ADMIN') and return unless user_has_any_role?(%w[GERENTE ADMIN])

            idempotent! do
              result = ::Financial::ReverseExpense.call(
                expense: @expense, actor: current_user,
                reason: params[:reason],
                reversed_at: params[:reversed_at]
              )
              if result.success?
                render json: serialize(result[:expense]), status: :ok
              else
                render json: { errors: result.errors }, status: :unprocessable_entity
              end
            end
          end

          private

          def set_expense
            @expense = ::Financial::Expense.for_account(current_account.id).find(params[:id])
          end

          def expense_params
            params.require(:expense).permit(
              :description, :financial_dre_category_id, :financial_bank_account_id,
              :supplier_name, :amount_cents, :status, :payment_method,
              :competence_date, :due_date, :installments_count, :installment_number,
              :notes
            )
          end

          def meta_for(scope)
            {
              total_to_pay_cents: scope.where(status: %w[pendente vencido]).sum('amount_cents - paid_amount_cents'),
              total_recurring_cents: scope.recurring_origin.sum(:amount_cents),
              total_due_soon_cents: scope.due_soon(3).sum('amount_cents - paid_amount_cents'),
              total_count: scope.count
            }
          end

          def serialize(e)
            {
              id: e.id,
              description: e.description,
              category_id: e.financial_dre_category_id,
              bank_account_id: e.financial_bank_account_id,
              recurring_id: e.financial_recurring_expense_id,
              commission_entry_id: e.financial_commission_entry_id,
              supplier_name: e.supplier_name,
              status: e.status,
              amount_cents: e.amount_cents,
              paid_amount_cents: e.paid_amount_cents,
              remaining_cents: e.remaining_cents,
              payment_method: e.payment_method,
              competence_date: e.competence_date,
              due_date: e.due_date,
              paid_at: e.paid_at,
              installments_count: e.installments_count,
              installment_number: e.installment_number,
              notes: e.notes
            }
          end
        end
      end
    end
  end
end
