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
                                                  .includes(:financial_dre_category, :financial_bank_account)
            scope = scope.where(active: true) if params[:active] == 'true'
            data = scope.order(:name).map(&method(:serialize))

            payload = { data: data }
            payload[:summary] = build_summary(data) if params[:include_summary] == 'true'

            render json: payload
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
            cat  = r.financial_dre_category
            bank = r.financial_bank_account
            {
              id: r.id, name: r.name,
              category_id: r.financial_dre_category_id,
              category: cat ? { id: cat.id, name: cat.name, kind: cat.kind } : nil,
              bank_account_id: r.financial_bank_account_id,
              bank_account: bank ? { id: bank.id, name: bank.name } : nil,
              amount_cents: r.amount_cents,
              variable_amount: r.variable_amount,
              frequency: r.frequency, due_day: r.due_day,
              competence_rule: r.competence_rule,
              start_date: r.start_date, end_date: r.end_date,
              auto_pay: r.auto_pay, active: r.active
            }
          end

          # KPIs: contagem de ativas + total mensal estimado.
          # `monthly_estimate_cents` converte cada frequência pro equivalente
          # mensal: anual÷12, semestral÷6, trimestral÷3, bimestral÷2.
          # Despesas com `variable_amount=true` entram com 0 (não é estimável).
          FREQUENCY_DIVISORS = {
            'monthly'    => 1.0,
            'bimonthly'  => 2.0,
            'quarterly'  => 3.0,
            'semiannual' => 6.0,
            'annual'     => 12.0
          }.freeze

          def build_summary(serialized)
            actives = serialized.select { |r| r[:active] }
            monthly_estimate = actives.sum do |r|
              next 0 if r[:variable_amount]
              divisor = FREQUENCY_DIVISORS[r[:frequency]] || 1.0
              (r[:amount_cents].to_i / divisor).round
            end
            {
              active_count: actives.size,
              total_count: serialized.size,
              monthly_estimate_cents: monthly_estimate,
              annual_estimate_cents:  (monthly_estimate * 12).round
            }
          end
        end
      end
    end
  end
end
