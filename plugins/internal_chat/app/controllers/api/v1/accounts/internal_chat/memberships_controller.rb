require 'ostruct'

class Api::V1::Accounts::InternalChat::MembershipsController < Api::V1::Accounts::BaseController
  before_action :fetch_room
  before_action :fetch_membership, only: [:update, :destroy]

  # GET /rooms/:room_id/memberships
  def index
    authorize(@room, policy_class: InternalChat::MembershipPolicy)

    memberships = @room.memberships.active.includes(:user)
    render json: { data: memberships.map { |m| serialize_membership(m) } }
  end

  # POST /rooms/:room_id/memberships
  # body: { membership: { user_id: 42, role: 'member' } }
  #     ou { membership: { ai_agent_id: 'bea' } }   (atalho para a Bea)
  def create
    authorize(@room, policy_class: InternalChat::MembershipPolicy)
    return head :unprocessable_entity if @room.direct?

    if membership_params[:ai_agent_id].present? || membership_params[:add_bea]
      add_bea_membership
    else
      add_user_membership
    end
  end

  # PATCH /rooms/:room_id/memberships/:id
  def update
    authorize(@membership, policy_class: InternalChat::MembershipPolicy)

    @membership.update!(role: membership_params[:role])
    InternalChat::SystemMessageBuilder.call(
      room: @room, event: :role_changed, actor: Current.user,
      target: @membership.user, payload: { role: @membership.role }
    )
    broadcast_room_update
    render json: { data: serialize_membership(@membership) }
  end

  # DELETE /rooms/:room_id/memberships/:id
  # Pode ser auto-saída (left_at) ou remoção por admin.
  def destroy
    authorize(@membership, policy_class: InternalChat::MembershipPolicy)
    return head :unprocessable_entity if @room.direct?

    is_self = @membership.user_id == Current.user.id
    @membership.update!(left_at: Time.current)

    event = is_self ? :member_left : :member_removed
    target = if @membership.ai_agent_id.present?
               OpenStruct.new(available_name: InternalChat::BeaResolver::DISPLAY_LABEL)
             else
               @membership.user
             end
    InternalChat::SystemMessageBuilder.call(
      room: @room, event: event, actor: Current.user, target: target
    )
    broadcast_room_update
    head :ok
  end

  private

  def fetch_room
    @room = Current.account.internal_chat_rooms.find(params[:room_id])
  end

  def fetch_membership
    @membership = @room.memberships.find(params[:id])
  end

  def membership_params
    params.require(:membership).permit(:user_id, :ai_agent_id, :role, :add_bea)
  end

  def add_user_membership
    user = Current.account.users.find(membership_params[:user_id])
    membership = @room.memberships.find_or_initialize_by(user_id: user.id)
    membership.role = membership_params[:role] || 'member'
    membership.left_at = nil
    membership.save!

    InternalChat::SystemMessageBuilder.call(
      room: @room, event: :member_added, actor: Current.user, target: user
    )
    broadcast_room_update
    render json: { data: serialize_membership(membership) }, status: :created
  rescue ActiveRecord::RecordNotUnique
    # BE-8 (auditoria 2026-05-18): race entre 2 admins adicionando o
    # mesmo user simultaneamente. Unique index `(room_id, user_id)` já
    # protege no DB; rescue aqui pra UX idempotente (retorna o existente
    # em vez de 500). Não duplica system message — o vencedor da race
    # já disparou o `member_added`.
    membership = @room.memberships.find_by!(user_id: user.id)
    render json: { data: serialize_membership(membership) }, status: :ok
  end

  def add_bea_membership
    bea = InternalChat::BeaResolver.for_account(Current.account)
    return render json: { error: I18n.t('internal_chat.controllers.rooms.bea_unavailable') }, status: :unprocessable_entity unless bea

    membership = @room.memberships.find_or_initialize_by(ai_agent_id: bea.id)
    membership.role = 'member'
    membership.left_at = nil
    membership.save!

    pseudo_target = OpenStruct.new(available_name: InternalChat::BeaResolver::DISPLAY_LABEL)
    InternalChat::SystemMessageBuilder.call(
      room: @room, event: :member_added, actor: Current.user, target: pseudo_target
    )
    broadcast_room_update
    render json: { data: serialize_membership(membership) }, status: :created
  end

  def serialize_membership(m)
    is_ai = m.ai_agent_id.present?
    {
      id: m.id,
      user_id: m.user_id,
      ai_agent_id: m.ai_agent_id,
      role: m.role,
      name: is_ai ? InternalChat::BeaResolver::DISPLAY_LABEL : m.user&.available_name,
      avatar_url: m.user&.respond_to?(:avatar_url) ? m.user&.avatar_url : nil,
      is_ai: is_ai,
      joined_at: m.joined_at,
      left_at: m.left_at,
    }
  end

  def broadcast_room_update
    payload = InternalChat::RoomSerializer.new(@room.reload, current_user: Current.user).as_json
    user_ids = @room.memberships.active.where.not(user_id: nil).pluck(:user_id).uniq

    # ARCH-21 (audit 2026-05-19): fan-out via UserBroadcaster.call —
    # mesmo payload pra todos os membros (serializer já calculado com
    # Current.user). Cada membro só usa pra atualizar a listagem.
    InternalChat::UserBroadcaster.call(
      user_ids: user_ids,
      payload: { event: 'internal_chat.room.updated', data: payload }
    )
  end
end
