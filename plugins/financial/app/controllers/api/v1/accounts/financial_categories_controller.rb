module Api
  module V1
    module Accounts
      class FinancialCategoriesController < Api::V1::Accounts::BaseController
        before_action :set_category, only: [:show, :update, :destroy]

        # GET /api/v1/accounts/:account_id/financial/categories
        def index
          authorize FinancialCategory

          categories = Current.account.financial_categories.ordered

          categories = categories.where(category_type: params[:type]) if params[:type].present?
          categories = categories.roots if params[:roots_only] == 'true'

          render json: { categories: categories.map { |c| serialize(c) } }
        end

        # GET /api/v1/accounts/:account_id/financial/categories/:id
        def show
          authorize @category
          render json: { category: serialize(@category) }
        end

        # POST /api/v1/accounts/:account_id/financial/categories
        def create
          authorize FinancialCategory

          @category = Current.account.financial_categories.new(category_params)

          if @category.save
            render json: { category: serialize(@category) }, status: :created
          else
            render json: { errors: @category.errors.full_messages }, status: :unprocessable_entity
          end
        end

        # PATCH /api/v1/accounts/:account_id/financial/categories/:id
        def update
          authorize @category

          if @category.update(category_params)
            render json: { category: serialize(@category) }
          else
            render json: { errors: @category.errors.full_messages }, status: :unprocessable_entity
          end
        end

        # DELETE /api/v1/accounts/:account_id/financial/categories/:id
        def destroy
          authorize @category

          return render json: { error: 'Não é possível remover categorias padrão' }, status: :forbidden if @category.is_default?

          @category.destroy!
          render json: { message: 'Categoria removida com sucesso' }
        end

        private

        def set_category
          @category = Current.account.financial_categories.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render json: { error: 'Categoria não encontrada' }, status: :not_found
        end

        def category_params
          params.require(:financial_category).permit(
            :name, :category_type, :cost_type, :parent_id,
            :color, :icon, :position
          )
        end

        def serialize(c)
          {
            id: c.id,
            name: c.name,
            category_type: c.category_type,
            cost_type: c.cost_type,
            parent_id: c.parent_id,
            color: c.color,
            icon: c.icon,
            is_default: c.is_default,
            position: c.position,
            children_count: c.children.count
          }
        end
      end
    end
  end
end
