class Api::V1::Accounts::InternalChat::MentionsController < Api::V1::Accounts::BaseController
  before_action -> { authorize(InternalChat::Mention, policy_class: InternalChat::MentionPolicy) }

  # GET /accounts/:id/internal_chat/mentions
  # ?status=unread (default) | all
  def index
    scope = InternalChat::Mention
            .where(account_id: Current.account.id, user_id: Current.user.id)
            .includes(message: [:sender, :room])
            .recent
    scope = scope.unread unless params[:status] == 'all'
    scope = scope.limit(params[:limit].to_i.between?(1, 200) ? params[:limit].to_i : 50)

    render json: { data: scope.map { |m| serialize(m) } }
  end

  # POST /accounts/:id/internal_chat/mentions/mark_read
  # body: { message_ids: [..] }   ou vazio para todas
  def mark_read
    scope = InternalChat::Mention.where(account_id: Current.account.id, user_id: Current.user.id, read_at: nil)
    scope = scope.where(message_id: params[:message_ids]) if params[:message_ids].present?
    scope.update_all(read_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    head :ok
  end

  # GET /accounts/:id/internal_chat/mentions/unread_count
  def unread_count
    count = InternalChat::Mention.where(account_id: Current.account.id, user_id: Current.user.id, read_at: nil).count
    render json: { count: count }
  end

  private

  def serialize(mention)
    msg = mention.message
    {
      id: mention.id,
      message_id: mention.message_id,
      room_id: msg&.room_id,
      room_name: msg&.room ? msg.room.display_name_for(Current.user) : nil,
      sender: msg&.sender ? serialize_sender(msg.sender) : nil,
      content_preview: (msg&.content || '')[0, 200],
      read_at: mention.read_at,
      created_at: mention.created_at,
    }
  end

  # Mesmo formato usado em message_serializer/room_serializer pra User —
  # `available_name` cai pra display_name/name e `avatar_url` é o método
  # padrão do Chatwoot que retorna a URL pública do attachment ActiveStorage.
  def serialize_sender(user)
    {
      id: user.id,
      name: user.available_name,
      avatar_url: user.respond_to?(:avatar_url) ? user.avatar_url : nil,
    }
  end
end
