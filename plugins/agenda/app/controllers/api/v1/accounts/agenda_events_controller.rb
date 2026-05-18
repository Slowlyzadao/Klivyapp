class Api::V1::Accounts::AgendaEventsController < Api::V1::Accounts::BaseController
  before_action :agenda_event, except: [:index, :create]

  INDEX_MAX_RESULTS = 500

  def index
    authorize AgendaEvent
    scope = policy_scope(Current.account.agenda_events).includes(:user, :contact)
    scope = scope.where(user_id: params[:user_id]) if params[:user_id].present?
    scope = scope.where(contact_id: params[:contact_id]) if params[:contact_id].present?
    scope = scope.where(status: params[:status]) if params[:status].present?

    # Filtragem por período: overlap real (não containment).
    # Um evento aparece na janela se as faixas se cruzam — isso captura
    # corretamente eventos que cruzam a borda (ex.: domingo 23:30 → segunda 00:30).
    if params[:starts_at].present? && params[:ends_at].present?
      scope = scope.where('starts_at < ? AND ends_at > ?', params[:ends_at], params[:starts_at])
    elsif Rails.env.production?
      Rails.logger.warn("[Agenda] index sem range para account=#{Current.account.id}; aplicando cap=#{INDEX_MAX_RESULTS}")
    end

    @agenda_events = scope.order(:starts_at).limit(INDEX_MAX_RESULTS)
    fresh_when(@agenda_events)
  end

  def show
    authorize @agenda_event
  end

  def create
    authorize AgendaEvent
    safe_params = agenda_event_params
    safe_params = nullify_missing_contact(safe_params)
    safe_params = nullify_missing_category(safe_params)
    @agenda_event = Current.account.agenda_events.create!(safe_params)
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def update
    authorize @agenda_event
    safe_params = agenda_event_params
    safe_params = nullify_missing_contact(safe_params)
    safe_params = nullify_missing_category(safe_params)
    @agenda_event.update!(safe_params)
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def destroy
    authorize @agenda_event
    @agenda_event.destroy!
    head :ok
  end

  private

  def agenda_event
    @agenda_event ||= Current.account.agenda_events.find(params[:id])
  end

  def agenda_event_params
    params.require(:agenda_event).permit(
      :title, :description, :starts_at, :ends_at,
      :user_id, :contact_id, :category_id, :status, :event_type,
      custom_attributes: {}
    )
  end

  def nullify_missing_contact(safe_params)
    cid = safe_params[:contact_id]
    return safe_params if cid.blank?

    exists = Contact.where(account_id: Current.account.id, id: cid).exists?
    exists ? safe_params : safe_params.merge(contact_id: nil)
  end

  def nullify_missing_category(safe_params)
    cid = safe_params[:category_id]
    return safe_params if cid.blank?

    exists = Current.account.agenda_categories.where(id: cid).exists?
    exists ? safe_params : safe_params.merge(category_id: nil)
  end
end
