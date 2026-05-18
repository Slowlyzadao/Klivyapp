class Api::V1::Accounts::AgendaServicesController < Api::V1::Accounts::BaseController
  before_action :agenda_service, only: [:show, :update, :destroy, :reorder]
  before_action :check_authorization

  def index
    @services = Current.account.agenda_services.ordered
  end

  def show; end

  def create
    @service = Current.account.agenda_services.create!(service_params)
    render :show, status: :created
  end

  def update
    @service.update!(service_params)
    render :show
  end

  def destroy
    @service.destroy!
    head :ok
  end

  # PATCH /accounts/:account_id/agenda_services/reorder
  # Reordena os serviços. Body: { ids: [1, 2, 3] }
  def reorder
    ids = params[:ids]
    return head :unprocessable_entity unless ids.is_a?(Array)

    ActiveRecord::Base.transaction do
      ids.each_with_index do |id, index|
        Current.account.agenda_services.where(id: id).update_all(position: index)
      end
    end
    head :ok
  end

  private

  def agenda_service
    @service ||= Current.account.agenda_services.find(params[:id])
  end

  def service_params
    params.require(:agenda_service).permit(
      :name, :duration_minutes, :price, :requires_room, :color, :position,
      :default_category_id
    )
  end
end
