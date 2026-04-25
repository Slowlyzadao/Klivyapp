class Api::V1::Accounts::WaitingListEntriesController < Api::V1::Accounts::BaseController
  before_action :set_entry, only: [:update, :destroy]

  def index
    authorize WaitingListEntry
    @entries = Current.account.waiting_list_entries.includes(:contact).order(:created_at)
    render json: @entries.map { |e| serialize(e) }
  end

  # POST — cria ou atualiza (upsert por contact_id)
  def create
    authorize WaitingListEntry
    @entry = Current.account.waiting_list_entries.find_or_initialize_by(
      contact_id: entry_params[:contact_id]
    )
    @entry.assign_attributes(entry_params.except(:contact_id))

    if @entry.save
      render json: serialize(@entry), status: :ok
    else
      render json: { error: @entry.errors.full_messages.join(', ') },
             status: :unprocessable_entity
    end
  end

  def destroy
    authorize @entry
    @entry.destroy!
    head :no_content
  end

  private

  def set_entry
    @entry = Current.account.waiting_list_entries.find(params[:id])
  end

  def entry_params
    params.require(:waiting_list_entry).permit(
      :contact_id, :period, :specific_time, :notes,
      preferred_days: []
    )
  end

  def serialize(entry)
    contact = entry.contact
    {
      id: entry.id,
      contact_id: entry.contact_id,
      contact_name: contact.name,
      contact_phone: contact.phone_number,
      contact_avatar: contact.avatar_url,
      period: entry.period,
      specific_time: entry.specific_time,
      preferred_days: entry.preferred_days || [],
      notes: entry.notes,
      created_at: entry.created_at
    }
  end
end
