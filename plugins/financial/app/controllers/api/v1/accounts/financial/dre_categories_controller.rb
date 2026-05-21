module Api
  module V1
    module Accounts
      module Financial
        class DreCategoriesController < BaseController
          # Setup wizard precisa criar categorias antes do setup estar completo.
          skip_before_action :ensure_setup_complete!
          before_action :set_category, only: %i[show update destroy]

          def index
            categories = scope.ordered
            categories = categories.where(kind: params[:kind]) if params[:kind].present?
            categories = categories.where(active: true) if params[:active] == 'true'
            render json: { data: categories.map { |c| serialize(c) } }
          end

          def show
            render json: serialize(@category)
          end

          def create
            require_role!('GERENTE', 'ADMIN') and return unless user_has_any_role?(%w[GERENTE ADMIN])

            idempotent_optional! do
              category = scope.new(category_params)
              if category.save
                render json: serialize(category), status: :created
              else
                render json: { errors: category.errors.full_messages }, status: :unprocessable_entity
              end
            end
          end

          def update
            require_role!('GERENTE', 'ADMIN') and return unless user_has_any_role?(%w[GERENTE ADMIN])

            if @category.update(category_params)
              render json: serialize(@category)
            else
              render json: { errors: @category.errors.full_messages }, status: :unprocessable_entity
            end
          end

          def destroy
            require_role!('ADMIN') and return unless user_has_any_role?(%w[ADMIN])
            return render(json: { error: 'categoria default não pode ser excluída' }, status: :unprocessable_entity) if @category.default?
            return render(json: { error: 'categoria possui lançamentos. Migre antes de excluir.' }, status: :unprocessable_entity) if @category.has_entries?

            @category.soft_delete!(user: current_user)
            head :no_content
          end

          private

          def scope
            ::Financial::DreCategory.for_account(current_account.id)
          end

          def set_category
            @category = scope.find(params[:id])
          end

          def category_params
            params.require(:category).permit(:name, :kind, :parent_id, :color, :icon, :active, :position)
                  .merge(account_id: current_account.id)
          end

          def serialize(c)
            {
              id: c.id,
              name: c.name,
              kind: c.kind,
              parent_id: c.parent_id,
              color: c.color,
              icon: c.icon,
              is_default: c.is_default,
              active: c.active,
              position: c.position
            }
          end
        end
      end
    end
  end
end
