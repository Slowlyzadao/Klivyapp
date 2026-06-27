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
class AiAgent::Memory::CrossConversationHistory
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

    entries = recent_desc.reverse.map do |m|
      {
        role: m.incoming? ? 'user' : 'assistant',
        content: entry_content(m)
      }
    end
    merge_consecutive(entries).reject { |e| e[:content].empty? }
  end

  private

  # Conteúdo do item de histórico. Mídia sem texto (imagem/vídeo — áudio é
  # transcrito pra dentro de content) vira placeholder; senão o LLM veria um
  # turno vazio e perderia o fato de que o paciente mandou algo.
  def entry_content(message)
    text = message.content.to_s.strip

    # Follow-up automático: rotula pro LLM saber que foi uma mensagem
    # proativa do sistema — sem o rótulo, o "Olá, Fulano" do follow-up
    # parece reabertura de conversa e a Bea recumprimenta o paciente.
    if text.present? && message.content_attributes.is_a?(Hash) && message.content_attributes['ai_follow_up']
      return "[follow-up automático enviado pela clínica — NÃO é início de conversa]: #{text}"
    end
    return text if text.present?

    type = message.attachments.first&.file_type.to_s
    type.present? ? "[paciente enviou: #{type}]" : ''
  end

  # Bolhas consecutivas do mesmo lado viram UM item (a Bea posta 2-3
  # mensagens por turno via MessageChunker) — menos itens, conversa mais
  # legível pro LLM e a janela de N mensagens rende mais turnos.
  def merge_consecutive(entries)
    entries.each_with_object([]) do |entry, acc|
      if acc.last && acc.last[:role] == entry[:role]
        acc.last[:content] = [acc.last[:content], entry[:content]].reject(&:empty?).join("\n")
      else
        acc << entry.dup
      end
    end
  end
end
