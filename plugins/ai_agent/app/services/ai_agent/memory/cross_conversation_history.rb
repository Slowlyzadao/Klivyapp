module AiAgent
  module Memory
    # Builds Bea's per-turn history WIDER than the current conversation:
    # pulls non-private messages from ALL conversations of the same
    # contact within the last 24 hours, capped at the most recent N
    # messages. Replaces per-conversation lookup so Bea remembers what
    # happened even if the previous conversation got resolved/closed.
    #
    # Cascade delete is automatic: when Chatwoot deletes a Contact, its
    # conversations + messages go with it. We store nothing of our own
    # here — pure derived view on top of Chatwoot data.
    #
    # Privacy: skips `private: true` messages (internal notes never
    # leaked to the LLM).
    class CrossConversationHistory
      DEFAULT_LIMIT = 10
      DEFAULT_TTL_HOURS = 24

      def initialize(account_id:, contact_id:, current_message:, limit: DEFAULT_LIMIT, ttl_hours: DEFAULT_TTL_HOURS)
        @account_id = account_id
        @contact_id = contact_id
        @current_message = current_message
        @limit = limit
        @ttl_hours = ttl_hours
      end

      # Returns array of `{ role: 'user'|'assistant', content: '...' }`,
      # in chronological order (oldest first), excluding the current
      # incoming message itself. Empty array if contact is brand new
      # (zero prior messages within window).
      def build
        return [] if @contact_id.blank?

        cutoff = @current_message.created_at - @ttl_hours.hours

        # `Message` tem `default_scope { order(created_at: :asc) }` —
        # `.order(...DESC)` é silenciosamente sobrescrito. `reorder`
        # força DESC pra que o LIMIT pegue as N mais recentes (não as
        # N mais antigas que caberiam dentro da janela). Em seguida
        # invertemos pra cronológico (oldest → newest), que é o que
        # o LLM precisa pra entender o fluxo da conversa.
        recent_desc = ::Message
                      .joins(:conversation)
                      .where(conversations: { contact_id: @contact_id, account_id: @account_id })
                      .where(message_type: %i[incoming outgoing])
                      .where(private: false)
                      .where('messages.created_at >= ?', cutoff)
                      .where('messages.id < ?', @current_message.id)
                      .reorder('messages.created_at DESC, messages.id DESC')
                      .limit(@limit)
                      .to_a

        recent_desc.reverse.map do |m|
          {
            role: m.incoming? ? 'user' : 'assistant',
            content: m.content.to_s
          }
        end
      end
    end
  end
end
