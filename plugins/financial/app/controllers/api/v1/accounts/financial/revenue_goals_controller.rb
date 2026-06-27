module Api
  module V1
    module Accounts
      module Financial
        # Metas de Receita — canon Setup #8 (2026-05-23).
        # CRUD completo com 3 tiers (Mínima/Principal/Desafio), kinds
        # (total/por_categoria/por_agente) e métricas (currency/count).
        class RevenueGoalsController < BaseController
          skip_before_action :ensure_setup_complete!
          before_action :require_manager!
          before_action :set_goal, only: %i[show update destroy]

          def index
            scope = ::Financial::RevenueGoal.for_account(current_account.id)
                                              .includes(:financial_dre_category, :professional)
            scope = scope.where(active: true)  if params[:active] == 'true'
            scope = scope.where(active: false) if params[:active] == 'false'
            scope = scope.order(active: :desc, start_date: :desc)

            render json: { data: scope.map(&method(:serialize)) }
          end

          def show
            render json: serialize(@goal)
          end

          def create
            idempotent_optional! do
              goal = ::Financial::RevenueGoal.new(goal_params.merge(account_id: current_account.id))
              if goal.save
                render json: serialize(goal), status: :created
              else
                render json: { errors: goal.errors.full_messages }, status: :unprocessable_entity
              end
            end
          end

          def update
            if @goal.update(goal_params)
              render json: serialize(@goal)
            else
              render json: { errors: @goal.errors.full_messages }, status: :unprocessable_entity
            end
          end

          # DELETE vira "Encerrar" no canon: ativa=false (mantém histórico).
          def destroy
            @goal.encerrar!(user: current_user)
            render json: serialize(@goal)
          end

          # POST /financial/v2/revenue_goals/upsert — legacy compat.
          # Mantido pra UI antiga, mas redireciona pra create (validação Rails).
          def upsert
            create
          end

          private

          def require_manager!
            render(json: { error: 'forbidden' }, status: :forbidden) unless user_has_any_role?(%w[GERENTE ADMIN])
          end

          def set_goal
            @goal = ::Financial::RevenueGoal.for_account(current_account.id).find(params[:id])
          end

          def goal_params
            params.require(:revenue_goal).permit(
              :name, :kind, :metric,
              :financial_dre_category_id, :professional_id,
              :start_date, :end_date,
              :min_target_cents, :target_cents, :stretch_target_cents,
              :min_target_qty,   :target_qty,   :stretch_target_qty,
              :active
            )
          end

          def serialize(g)
            cat  = g.financial_dre_category
            prof = g.professional
            actual = g.actual_value
            {
              id: g.id,
              name: g.name,
              kind: g.kind,
              metric: g.metric,
              category_id: g.financial_dre_category_id,
              category: cat ? { id: cat.id, name: cat.name, kind: cat.kind } : nil,
              professional_id: g.professional_id,
              professional: prof ? { id: prof.id, name: prof.name, avatar_url: prof.try(:avatar_url).presence } : nil,
              start_date: g.start_date,
              end_date: g.end_date,
              # Tiers — em centavos OU qty conforme metric.
              min_target_cents:     g.min_target_cents,
              target_cents:         g.target_cents,
              stretch_target_cents: g.stretch_target_cents,
              min_target_qty:       g.min_target_qty,
              target_qty:           g.target_qty,
              stretch_target_qty:   g.stretch_target_qty,
              # ATUAL calculado (sum/count de entries no período)
              actual_value: actual,
              progress_percent: g.progress_percent(actual_override: actual),
              active: g.active
            }
          end
        end
      end
    end
  end
end
