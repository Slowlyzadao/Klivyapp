module AiAgent
  module Api
    module V1
      module Accounts
        # CRUD das regras de follow-up. Cada regra é por conta. A clínica
        # gerencia pela página `/accounts/:id/ai_agent/follow_ups` (rota
        # Vue do plugin). Não tem nada de Captain — é UI nova totalmente
        # nossa em cima do plugin ai_agent.
        class FollowUpRulesController < ::Api::V1::Accounts::BaseController
          before_action :set_rule, only: %i[show update destroy]

          def index
            rules = ::AiAgent::FollowUpRule
                    .where(account_id: Current.account.id)
                    .ordered
            render json: rules.map { |r| serialize(r) }
          end

          def show
            render json: serialize(@rule)
          end

          def create
            rule = ::AiAgent::FollowUpRule.new(rule_params.merge(account_id: Current.account.id))
            if rule.save
              render json: serialize(rule), status: :created
            else
              render json: { errors: rule.errors.full_messages }, status: :unprocessable_entity
            end
          end

          def update
            if @rule.update(rule_params)
              render json: serialize(@rule)
            else
              render json: { errors: @rule.errors.full_messages }, status: :unprocessable_entity
            end
          end

          def destroy
            @rule.destroy
            head :no_content
          end

          private

          def set_rule
            @rule = ::AiAgent::FollowUpRule.where(account_id: Current.account.id).find(params[:id])
          end

          def rule_params
            params.require(:follow_up_rule).permit(
              :name, :enabled, :position, :trigger_type, :offset_hours, :offset_unit,
              :context_brief, :max_per_target, :applies_to,
              status_filter: {}
            )
          end

          def serialize(rule)
            {
              id: rule.id,
              name: rule.name,
              enabled: rule.enabled,
              position: rule.position,
              trigger_type: rule.trigger_type,
              offset_hours: rule.offset_hours,
              offset_unit: rule.offset_unit,
              offset_seconds: rule.offset_seconds,
              applies_to: rule.applies_to,
              status_filter: rule.status_filter,
              context_brief: rule.context_brief,
              max_per_target: rule.max_per_target,
              created_at: rule.created_at,
              updated_at: rule.updated_at
            }
          end
        end
      end
    end
  end
end
