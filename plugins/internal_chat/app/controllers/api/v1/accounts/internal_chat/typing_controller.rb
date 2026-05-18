class Api::V1::Accounts::InternalChat::TypingController < Api::V1::Accounts::BaseController
  before_action :fetch_room
  before_action :authorize_room_access

  # POST /rooms/:room_id/typing
  # body: { active: true | false }
  # Broadcast efêmero — não persiste nada. Frontend usa debounce de ~3s.
  def create
    active = ActiveModel::Type::Boolean.new.cast(params[:active])
    payload = {
      event: 'internal_chat.typing',
      data: {
        account_id: @room.account_id,
        room_id: @room.id,
        user_id: Current.user.id,
        user_name: Current.user.available_name,
        active: active,
      },
    }
    @room.memberships.active.where.not(user_id: nil).pluck(:user_id).each do |uid|
      next if uid == Current.user.id

      user = User.find_by(id: uid)
      ActionCable.server.broadcast(user.pubsub_token, payload) if user
    end
    head :no_content
  end

  private

  def fetch_room
    @room = Current.account.internal_chat_rooms.find(params[:room_id])
  end

  def authorize_room_access
    return if @room.member?(Current.user)

    head :forbidden
  end
end
