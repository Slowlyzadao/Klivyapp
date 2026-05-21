module Api
  module V1
    module Accounts
      class CommissionRulesController < Api::V1::Accounts::BaseController
        before_action :set_rule, only: [:update, :destroy]

        def index
          authorize :commission_rule, :index?
          rules = Current.account.commission_rules
                         .includes(:professional, :financial_category)
                         .order(created_at: :desc)

          render json: rules.map { |r| serialize(r) }
        end

        def create
          authorize :commission_rule, :create?
          rule = Current.account.commission_rules.build(rule_params)
          rule.save!
          render json: serialize(rule), status: :created
        rescue ActiveRecord::RecordInvalid => e
          render json: { error: e.message }, status: :unprocessable_entity
        end

        def update
          authorize :commission_rule, :update?
          @rule.update!(rule_params)
          render json: serialize(@rule)
        rescue ActiveRecord::RecordInvalid => e
          render json: { error: e.message }, status: :unprocessable_entity
        end

        def destroy
          authorize :commission_rule, :destroy?
          @rule.destroy!
          head :no_content
        end

        private

        def set_rule
          @rule = Current.account.commission_rules.find(params[:id])
        end

        def rule_params
          params.require(:commission_rule).permit(
            :professional_id, :commission_type, :value,
            :financial_category_id, :procedure_name, :specialty,
            :valid_from, :valid_until, :active, :notes
          )
        end

        def serialize(rule)
          {
            id:                    rule.id,
            professional_id:       rule.professional_id,
            professional_name:     rule.professional&.name,
            commission_type:       rule.commission_type,
            value:                 rule.value.to_f,
            financial_category_id: rule.financial_category_id,
            category_name:         rule.financial_category&.name,
            procedure_name:        rule.procedure_name,
            specialty:             rule.specialty,
            valid_from:            rule.valid_from&.to_s,
            valid_until:           rule.valid_until&.to_s,
            active:                rule.active,
            notes:                 rule.notes,
            created_at:            rule.created_at.iso8601
          }
        end
      end
    end
  end
end
