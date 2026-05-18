module InternalChat
  # Extrai usuários e AI agents mencionados a partir do `content_attributes`.
  # Convenção:
  #   content_attributes['mentioned_user_ids']     => [..]   (humanos)
  #   content_attributes['mentioned_ai_agent_ids'] => [..]   (Bea, futuras IAs)
  #
  # Filtramos para garantir que o mencionado seja membro ativo da sala —
  # anti-spam e privacidade.
  class MentionExtractor
    Result = Struct.new(:user_ids, :ai_agent_ids, keyword_init: true)

    def self.call(message)
      user_ids = parse_ids(message, 'mentioned_user_ids')
      ai_ids   = parse_ids(message, 'mentioned_ai_agent_ids')

      # Reply em mensagem de IA conta como menção implícita — UX natural pra
      # quem responde em thread sem precisar @ de novo.
      ai_ids.concat(implicit_ai_mentions_from_reply(message))
      ai_ids.uniq!

      eligible_users = []
      if user_ids.any?
        eligible_users = message.room
                                .memberships
                                .where(user_id: user_ids, left_at: nil)
                                .pluck(:user_id)
      end

      eligible_ai = []
      if ai_ids.any?
        eligible_ai = message.room
                             .memberships
                             .where(ai_agent_id: ai_ids, left_at: nil)
                             .pluck(:ai_agent_id)
      end

      Result.new(user_ids: eligible_users, ai_agent_ids: eligible_ai)
    end

    def self.implicit_ai_mentions_from_reply(message)
      reply_to_id = message.content_attributes['in_reply_to']
      return [] if reply_to_id.blank?

      replied = ::InternalChat::Message
                .where(room_id: message.room_id, id: reply_to_id)
                .where.not(sender_ai_agent_id: nil)
                .pick(:sender_ai_agent_id)

      replied.present? ? [replied] : []
    end

    def self.parse_ids(message, key)
      Array(message.content_attributes[key]).map(&:to_i).uniq.reject(&:zero?)
    end
  end
end
