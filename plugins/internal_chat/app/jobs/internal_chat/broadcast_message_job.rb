module InternalChat
  # Faz fan-out da mensagem para o pubsub_token de cada usuário membro da sala
  # via ActionCable. Reaproveita o RoomChannel existente — cada usuário já está
  # inscrito em `stream_from pubsub_token` desde o login.
  class BroadcastMessageJob < ApplicationJob
    queue_as :default

    def perform(message_id)
      message = InternalChat::Message.find_by(id: message_id)
      return unless message

      message_payload = {
        event: 'internal_chat.message.created',
        data: InternalChat::MessageSerializer.new(message).as_json,
      }

      mention_user_ids = message.mentions.pluck(:user_id).to_set
      recipient_ids = message.room.memberships
                                  .where.not(user_id: nil)
                                  .where(left_at: nil)
                                  .pluck(:user_id)

      User.where(id: recipient_ids).find_each do |user|
        ActionCable.server.broadcast(user.pubsub_token, message_payload)

        next unless mention_user_ids.include?(user.id)

        mention_payload = {
          event: 'internal_chat.mention.created',
          data: {
            account_id: message.room.account_id,
            room_id: message.room_id,
            message_id: message.id,
            mentioned_at: message.created_at,
            sender: message_payload[:data][:sender],
            content_preview: (message.content || '')[0, 140],
          },
        }
        ActionCable.server.broadcast(user.pubsub_token, mention_payload)
        InternalChat::Telemetry.track('mention_received',
                                      account_id: message.room.account_id,
                                      room_id: message.room_id,
                                      message_id: message.id,
                                      user_id: user.id)
      end
    end
  end
end
