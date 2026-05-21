module Api
  module V1
    module Accounts
      module Financial
        # Wizard de configuração inicial. Canon F-04.
        # GET /financial/v2/setup → estado atual
        # POST /financial/v2/setup/complete_step → marca passo como feito
        class SetupController < BaseController
          # remove o ensure_setup_complete! para os endpoints do próprio wizard
          skip_before_action :ensure_setup_complete!

          def show
            state = ::Financial::SetupState.for_account(current_account.id)
            render json: serialize(state)
          end

          def complete_step
            require_role!('ADMIN') and return unless user_has_any_role?(%w[ADMIN GERENTE])

            state = ::Financial::SetupState.for_account(current_account.id)
            step = params[:step].to_s
            allowed = %w[step_categories_done step_bank_accounts_done step_commission_rules_done step_recurring_expenses_done step_revenue_goal_done]
            return render(json: { error: "step inválido: #{step}" }, status: :unprocessable_entity) unless allowed.include?(step)

            state.update!(
              step => true,
              status: 'in_progress'
            )
            if state.required_steps_done? && state.status != 'completed'
              state.update!(status: 'completed', completed_at: Time.current, completed_by_id: current_user.id)
            end

            render json: serialize(state)
          end

          private

          def serialize(state)
            {
              status: state.status,
              progress_percent: state.progress_percent,
              required_steps_done: state.required_steps_done?,
              all_steps_done: state.all_steps_done?,
              steps: {
                categories: state.step_categories_done,
                bank_accounts: state.step_bank_accounts_done,
                commission_rules: state.step_commission_rules_done,
                recurring_expenses: state.step_recurring_expenses_done,
                revenue_goal: state.step_revenue_goal_done
              },
              completed_at: state.completed_at
            }
          end
        end
      end
    end
  end
end
