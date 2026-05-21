module Api
  module V1
    module Accounts
      module Financial
        class CommissionRulesController < BaseController
          skip_before_action :ensure_setup_complete!
          before_action :require_admin!
          before_action :set_rule, only: %i[show update destroy]

          def index
            scope = ::Financial::CommissionRule.for_account(current_account.id)
            scope = scope.where(professional_id: params[:professional_id]) if params[:professional_id].present?
            scope = scope.active_rules if params[:active] == 'true'
            scope = scope.includes(:professional, :financial_dre_category)
            render json: { data: scope.order(valid_from: :desc).map(&method(:serialize)) }
          end

          def show
            render json: serialize(@rule)
          end

          def create
            idempotent_optional! do
              rule = ::Financial::CommissionRule.new(rule_params.merge(account_id: current_account.id))
              if rule.save
                render json: serialize(rule), status: :created
              else
                render json: { errors: rule.errors.full_messages }, status: :unprocessable_entity
              end
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
            @rule.soft_delete!(user: current_user)
            head :no_content
          end

          private

          def require_admin!
            render(json: { error: 'forbidden' }, status: :forbidden) unless user_has_any_role?(%w[ADMIN])
          end

          def set_rule
            @rule = ::Financial::CommissionRule.for_account(current_account.id).find(params[:id])
          end

          def rule_params
            params.require(:commission_rule).permit(
              :professional_id, :financial_dre_category_id, :kind, :base,
              :percent_basis_points, :fixed_amount_cents, :procedure_name, :specialty,
              :deduct_mdr, :deduct_lab, :valid_from, :valid_until, :active
            )
          end

          def serialize(r)
            prof = r.professional
            cat = r.financial_dre_category
            {
              id: r.id,
              professional_id: r.professional_id,
              professional: prof ? {
                id: prof.id,
                name: prof.name,
                avatar_url: prof.try(:resolved_avatar_url)
              } : nil,
              # Mantém professional_name pra compatibilidade com UI antiga.
              professional_name: prof&.name,
              financial_dre_category_id: r.financial_dre_category_id,
              category_id: r.financial_dre_category_id, # alias retrocompat
              category: cat ? { id: cat.id, name: cat.name, kind: cat.kind } : nil,
              kind: r.kind,
              base: r.base,
              percent: r.percent,
              percent_basis_points: r.percent_basis_points,
              fixed_amount_cents: r.fixed_amount_cents,
              procedure_name: r.procedure_name,
              specialty: r.specialty,
              deduct_mdr: r.deduct_mdr,
              deduct_lab: r.deduct_lab,
              valid_from: r.valid_from,
              valid_until: r.valid_until,
              active: r.active
            }
          end
        end
      end
    end
  end
end
