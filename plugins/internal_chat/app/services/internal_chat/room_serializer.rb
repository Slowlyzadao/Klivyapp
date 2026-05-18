module InternalChat
  class RoomSerializer
    def initialize(room, current_user:)
      @room = room
      @current_user = current_user
    end

    def as_json
      memberships = @room.memberships.active.includes(:user).to_a
      my_membership = memberships.find { |m| m.user_id == @current_user.id }
      last = @room.messages.visible.order(id: :desc).first

      {
        id: @room.id,
        # account_id é obrigatório no payload de cable events (filtro do
        # ActionCableConnector core).
        account_id: @room.account_id,
        kind: @room.kind,
        name: @room.display_name_for(@current_user),
        description: @room.description,
        avatar_url: avatar_url_for(memberships),
        archived_at: @room.archived_at,
        muted_until: my_membership&.muted_until,
        last_message_at: @room.last_message_at,
        last_message: last ? InternalChat::MessageSerializer.new(last).as_json : nil,
        unread_count: my_membership ? my_membership.unread_count : 0,
        members: memberships.map { |m| membership_payload(m) },
        created_by_user_id: @room.created_by_user_id,
        created_at: @room.created_at,
      }
    end

    private

    def avatar_url_for(memberships)
      return @room.avatar_url if @room.group?

      other = memberships.map(&:user).compact.find { |u| u.id != @current_user.id }
      other&.respond_to?(:avatar_url) ? other.avatar_url : nil
    end

    def membership_payload(m)
      is_ai = m.ai_agent_id.present?
      {
        id: m.id,
        user_id: m.user_id,
        ai_agent_id: m.ai_agent_id,
        role: m.role,
        name: is_ai ? InternalChat::BeaResolver::DISPLAY_LABEL : m.user&.available_name,
        avatar_url: m.user&.respond_to?(:avatar_url) ? m.user&.avatar_url : nil,
        is_ai: is_ai,
        last_read_message_id: m.last_read_message_id,
      }
    end
  end
end
