module Api
  module V1
    module Accounts
      module Financial
        class RevenueGoalsController < BaseController
          skip_before_action :ensure_setup_complete!
          before_action :require_manager!

          def index
            scope = ::Financial::RevenueGoal.for_account(current_account.id)
            scope = scope.where(year: params[:year]) if params[:year].present?
            render json: { data: scope.order(:year, :period, :month, :quarter).map(&method(:serialize)) }
          end

          def upsert
            attrs = goal_params.merge(account_id: current_account.id)
            goal = ::Financial::RevenueGoal.find_or_initialize_by(
              account_id: current_account.id,
              period: attrs[:period],
              year: attrs[:year],
              month: attrs[:month],
              quarter: attrs[:quarter]
            )
            goal.amount_cents = attrs[:amount_cents]
            if goal.save
              render json: serialize(goal), status: :ok
            else
              render json: { errors: goal.errors.full_messages }, status: :unprocessable_entity
            end
          end

          def destroy
            goal = ::Financial::RevenueGoal.for_account(current_account.id).find(params[:id])
            goal.destroy
            head :no_content
          end

          private

          def require_manager!
            render(json: { error: 'forbidden' }, status: :forbidden) unless user_has_any_role?(%w[GERENTE ADMIN])
          end

          def goal_params
            params.require(:revenue_goal).permit(:period, :year, :month, :quarter, :amount_cents)
          end

          def serialize(g)
            {
              id: g.id, period: g.period, year: g.year, month: g.month,
              quarter: g.quarter, amount_cents: g.amount_cents
            }
          end
        end
      end
    end
  end
end
