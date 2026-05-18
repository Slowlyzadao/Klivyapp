class Api::V1::Accounts::AgendaCategoriesController < Api::V1::Accounts::BaseController
  before_action :fetch_category, only: [:show, :update, :destroy]
  before_action -> { check_authorization(Agenda::Category) }

  def index
    scope = Current.account.agenda_categories.ordered
    scope = scope.active unless ActiveModel::Type::Boolean.new.cast(params[:include_inactive])
    @categories = decorate_with_counts(scope.to_a)
  end

  def show; end

  def create
    @category = Current.account.agenda_categories.create!(category_params)
    render :show, status: :created
  end

  def update
    @category.update!(category_params)
    render :show
  end

  # Soft delete: apenas marca como inativa para preservar referências históricas
  # nos eventos. Sem hard-delete intencional — eventos antigos continuam vinculados.
  def destroy
    @category.update!(active: false)
    head :ok
  end

  # PATCH /accounts/:account_id/agenda_categories/reorder
  # Body: { ids: [1, 2, 3] }
  def reorder
    ids = params[:ids]
    return head :unprocessable_entity unless ids.is_a?(Array)

    ActiveRecord::Base.transaction do
      ids.each_with_index do |id, index|
        Current.account.agenda_categories.where(id: id).update_all(position: index)
      end
    end
    head :ok
  end

  private

  def fetch_category
    @category = Current.account.agenda_categories.find(params[:id])
  end

  def category_params
    params.require(:agenda_category).permit(:name, :color, :position, :active)
  end

  # Anexa appointments_count em uma única query agregada para evitar N+1.
  def decorate_with_counts(categories)
    counts = AgendaEvent.where(account_id: Current.account.id, category_id: categories.map(&:id))
                       .group(:category_id)
                       .count
    categories.each do |c|
      c.define_singleton_method(:appointments_count_attr) { counts[c.id] || 0 }
    end
    categories
  end
end
