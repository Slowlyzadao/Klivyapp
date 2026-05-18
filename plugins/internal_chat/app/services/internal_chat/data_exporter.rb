module InternalChat
  # Exporta tudo o que um usuário gerou no chat interno (LGPD Art. 18 — direito
  # de portabilidade). Retorna hash serializável; quem chama escreve em
  # JSON/zip conforme a política.
  class DataExporter
    def self.call(user:)
      new(user).call
    end

    def initialize(user)
      @user = user
    end

    def call
      {
        user_id: @user.id,
        exported_at: Time.current.iso8601,
        rooms: rooms_payload,
        messages: messages_payload,
        mentions_received: mentions_payload,
      }
    end

    private

    def rooms_payload
      InternalChat::Membership.where(user_id: @user.id).includes(:room).map do |m|
        {
          room_id: m.room_id,
          role: m.role,
          joined_at: m.joined_at,
          left_at: m.left_at,
          room_kind: m.room.kind,
          room_name: m.room.name,
        }
      end
    end

    def messages_payload
      InternalChat::Message.where(sender_user_id: @user.id).order(:created_at).map do |msg|
        {
          message_id: msg.id,
          room_id: msg.room_id,
          content: msg.content,
          content_type: msg.content_type,
          content_attributes: msg.content_attributes,
          deleted_at: msg.deleted_at,
          created_at: msg.created_at,
          attachment_count: msg.attachments.count,
        }
      end
    end

    def mentions_payload
      InternalChat::Mention.where(user_id: @user.id).order(:created_at).map do |m|
        {
          mention_id: m.id,
          message_id: m.message_id,
          read_at: m.read_at,
          created_at: m.created_at,
        }
      end
    end
  end
end
