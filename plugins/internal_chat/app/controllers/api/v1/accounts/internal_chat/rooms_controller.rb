class Api::V1::Accounts::InternalChat::RoomsController < Api::V1::Accounts::BaseController
  before_action :fetch_room, only: [:show, :update, :destroy, :archive, :unarchive, :mute, :unmute, :update_avatar, :remove_avatar]
  before_action :authorize_action

  def authorize_action
    # Pundit precisa do registro real (não da classe) para checar membership.
    target = @room || InternalChat::Room
    authorize(target, "#{action_name}?".to_sym)
  end

  def index
    # Postgres rejeita DISTINCT + ORDER BY com expressões fora do SELECT, então
    # buscamos os ids via subquery e ordenamos sem JOIN (mais barato também).
    room_ids = InternalChat::Membership
               .where(user_id: Current.user.id, left_at: nil)
               .pluck(:room_id)
    rooms = Current.account.internal_chat_rooms
                   .where(id: room_ids)
                   .not_archived
                   .recent
    render json: { data: rooms.map { |r| InternalChat::RoomSerializer.new(r, current_user: Current.user).as_json } }
  end

  def show
    render json: { data: InternalChat::RoomSerializer.new(@room, current_user: Current.user).as_json }
  end

  def create
    result = InternalChat::RoomCreator.call(
      account: Current.account,
      current_user: Current.user,
      kind: room_params[:kind] || 'direct',
      member_user_ids: room_params[:member_user_ids],
      name: room_params[:name],
      description: room_params[:description],
      add_bea: ActiveModel::Type::Boolean.new.cast(room_params[:add_bea]),
    )
    render json: { data: InternalChat::RoomSerializer.new(result.room, current_user: Current.user).as_json },
           status: result.created ? :created : :ok
  rescue ArgumentError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def update
    name_was = @room.name
    description_was = @room.description
    @room.update!(room_params.slice(:name, :description, :archived_at))

    if @room.group?
      if @room.name != name_was && @room.name.present?
        InternalChat::SystemMessageBuilder.call(
          room: @room, event: :renamed, actor: Current.user, payload: { name: @room.name }
        )
      end
      if @room.description != description_was
        InternalChat::SystemMessageBuilder.call(
          room: @room, event: :description_changed, actor: Current.user
        )
      end
    end
    render json: { data: InternalChat::RoomSerializer.new(@room, current_user: Current.user).as_json }
  end

  def destroy
    # Broadcast ANTES de destruir, pra que cada cliente conectado consiga
    # remover a sala da listagem em tempo real.
    member_user_ids = @room.memberships.where.not(user_id: nil).pluck(:user_id).uniq
    payload = { event: 'internal_chat.room.deleted',
                data: { account_id: @room.account_id, room_id: @room.id } }
    @room.destroy!
    member_user_ids.each do |uid|
      user = User.find_by(id: uid)
      ActionCable.server.broadcast(user.pubsub_token, payload) if user
    end
    InternalChat::Telemetry.track('room_deleted',
                                  account_id: Current.account.id,
                                  room_id: params[:id],
                                  user_id: Current.user.id)
    head :ok
  end

  # PATCH /rooms/:id/avatar
  # multipart com `avatar` (file). Atualiza imagem do grupo.
  def update_avatar
    return head :unprocessable_entity if params[:avatar].blank?

    @room.avatar.attach(params[:avatar])
    return render json: { errors: @room.errors.full_messages }, status: :unprocessable_entity unless @room.save

    broadcast_room_update
    render json: { data: InternalChat::RoomSerializer.new(@room.reload, current_user: Current.user).as_json }
  end

  # DELETE /rooms/:id/avatar
  def remove_avatar
    @room.avatar.purge if @room.avatar.attached?
    @room.update!(avatar_url: nil)
    broadcast_room_update
    render json: { data: InternalChat::RoomSerializer.new(@room.reload, current_user: Current.user).as_json }
  end

  # PATCH /rooms/:id/archive
  def archive
    return head :forbidden unless can_archive?

    @room.update!(archived_at: Time.current)
    InternalChat::Telemetry.track('room_archived',
                                  account_id: @room.account_id, room_id: @room.id)
    render json: { data: InternalChat::RoomSerializer.new(@room, current_user: Current.user).as_json }
  end

  # PATCH /rooms/:id/unarchive
  def unarchive
    return head :forbidden unless can_archive?

    @room.update!(archived_at: nil)
    render json: { data: InternalChat::RoomSerializer.new(@room, current_user: Current.user).as_json }
  end

  # PATCH /rooms/:id/mute
  # body: { mute_until: <iso8601> | null }   nil = mutar indefinido
  def mute
    membership = membership_for_current_user
    return head :unprocessable_entity unless membership

    until_time = params[:mute_until].present? ? Time.zone.parse(params[:mute_until]) : 100.years.from_now
    membership.update!(muted_until: until_time)
    InternalChat::Telemetry.track('room_muted',
                                  account_id: @room.account_id, room_id: @room.id,
                                  user_id: Current.user.id)
    render json: { data: { room_id: @room.id, muted_until: membership.muted_until } }
  end

  # DELETE /rooms/:id/mute
  def unmute
    membership = membership_for_current_user
    return head :unprocessable_entity unless membership

    membership.update!(muted_until: nil)
    render json: { data: { room_id: @room.id, muted_until: nil } }
  end

  def unread_summary
    room_ids = InternalChat::Membership
               .where(user_id: Current.user.id, left_at: nil)
               .where(room_id: Current.account.internal_chat_rooms.select(:id))
               .pluck(:room_id, :id)

    summary = {}
    InternalChat::Membership.where(id: room_ids.map(&:last)).find_each do |m|
      summary[m.room_id] = m.unread_count
    end
    render json: { data: summary, total: summary.values.sum }
  end

  private

  def fetch_room
    @room = Current.account.internal_chat_rooms.find(params[:id])
  end

  def membership_for_current_user
    @room.memberships.find_by(user_id: Current.user.id, left_at: nil)
  end

  def can_archive?
    return true if Current.account_user.administrator?

    @room.memberships.where(user_id: Current.user.id, left_at: nil, role: %w[owner admin]).exists?
  end

  def room_params
    params.require(:room).permit(:kind, :name, :description, :archived_at, :add_bea, member_user_ids: [])
  end

  def broadcast_room_update
    payload = InternalChat::RoomSerializer.new(@room.reload, current_user: Current.user).as_json
    @room.memberships.where.not(user_id: nil).pluck(:user_id).uniq.each do |uid|
      user = User.find_by(id: uid)
      next unless user

      ActionCable.server.broadcast(
        user.pubsub_token,
        { event: 'internal_chat.room.updated', data: payload }
      )
    end
  end
end
