module Api
  module V1
    module Accounts
      module Financial
        # Wizard de configuração inicial — canon Setup #1..#8 (2026-05-23).
        # GET  /financial/v2/setup            → estado recalculado a partir do banco
        # POST /financial/v2/setup/complete_step → marca passo como feito manualmente
        #                                          (raramente necessário — refresh! cobre tudo)
        class SetupController < BaseController
          # Próprio wizard não exige setup completo (seria contraditório)
          skip_before_action :ensure_setup_complete!

          ALLOWED_STEPS = %w[
            step_categories_done
            step_bank_accounts_done
            step_payment_methods_done
            step_agent_profiles_done
            step_services_done
            step_commission_rules_done
            step_recurring_expenses_done
            step_revenue_goal_done
          ].freeze

          def show
            state = ::Financial::SetupState.for_account(current_account.id).refresh!
            render json: serialize(state)
          end

          def complete_step
            require_role!('ADMIN') and return unless user_has_any_role?(%w[ADMIN GERENTE])

            step = params[:step].to_s
            return render(json: { error: "step inválido: #{step}" }, status: :unprocessable_entity) unless ALLOWED_STEPS.include?(step)

            state = ::Financial::SetupState.for_account(current_account.id)
            state.update!(step => true, status: 'in_progress')
            state.refresh! # recalcula status final (pode virar 'completed' aqui)
            render json: serialize(state)
          end

          private

          def serialize(state)
            {
              status: state.status,
              progress_percent: state.progress_percent,
              required_progress_percent: state.required_progress_percent,
              required_steps_done: state.required_steps_done?,
              all_steps_done: state.all_steps_done?,
              steps: {
                categories:         state.step_categories_done,
                bank_accounts:      state.step_bank_accounts_done,
                payment_methods:    state.step_payment_methods_done,
                agent_profiles:     state.step_agent_profiles_done,
                services:           state.step_services_done,
                commission_rules:   state.step_commission_rules_done,
                recurring_expenses: state.step_recurring_expenses_done,
                revenue_goal:       state.step_revenue_goal_done
              },
              # Classificação canon — UI usa pra agrupar visualmente.
              required: %w[categories bank_accounts payment_methods],
              recommended: %w[agent_profiles services],
              optional: %w[commission_rules recurring_expenses revenue_goal],
              completed_at: state.completed_at
            }
          end
        end
      end
    end
  end
end
