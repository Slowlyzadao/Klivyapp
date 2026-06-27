module InternalChat
  # Gera mensagens "system" (entrar/sair/renomear). Não tem sender humano —
  # `sender_user_id` fica nulo. Renderizada como pílula central no UI.
  #
  # Eventos suportados:
  #   :member_added    -> "<actor> adicionou <target> ao grupo"
  #   :member_removed  -> "<actor> removeu <target> do grupo"
  #   :member_left     -> "<target> saiu do grupo"
  #   :role_changed    -> "<actor> definiu <target> como <role>"
  #   :renamed         -> "<actor> renomeou o grupo para <name>"
  #   :description_changed -> "<actor> alterou a descrição do grupo"
  class SystemMessageBuilder
    EVENTS = %i[member_added member_removed member_left role_changed renamed description_changed].freeze

    def self.call(room:, event:, actor: nil, target: nil, payload: {})
      new(room, event, actor, target, payload).call
    end

    def initialize(room, event, actor, target, payload)
      @room = room
      @event = event.to_sym
      @actor = actor
      @target = target
      @payload = payload || {}
    end

    def call
      raise ArgumentError, "evento inválido: #{@event}" unless EVENTS.include?(@event)

      message = @room.messages.create!(
        content: text,
        content_type: 'system',
        content_attributes: {
          system_event: @event.to_s,
          actor_id: @actor&.id,
          target_id: @target&.id,
          payload: @payload,
        },
      )
      @room.touch_last_message!(message.created_at)
      InternalChat::BroadcastMessageJob.perform_later(message.id)
      message
    end

    private

    # FE-16/17 (auditoria 2026-05-18): strings migradas pra I18n
    # (`internal_chat.system_messages.*`). Interpolação preserva
    # safe_label sanitization — vars vão pro template já limpas.
    def text
      a = safe_label(@actor&.available_name) || I18n.t('internal_chat.system_messages.system_actor')
      t = safe_label(@target&.available_name)
      case @event
      when :member_added
        I18n.t('internal_chat.system_messages.member_added', actor: a, target: t)
      when :member_removed
        I18n.t('internal_chat.system_messages.member_removed', actor: a, target: t)
      when :member_left
        I18n.t('internal_chat.system_messages.member_left', actor: t || a)
      when :role_changed
        I18n.t('internal_chat.system_messages.role_changed',
               actor: a, target: t, role: safe_label(@payload[:role]))
      when :renamed
        I18n.t('internal_chat.system_messages.renamed',
               actor: a, name: safe_label(@payload[:name]))
      when :description_changed
        I18n.t('internal_chat.system_messages.description_changed', actor: a)
      end
    end

    # Defesa em profundidade contra BE-14 (auditoria 2026-05-18). O frontend
    # atual renderiza system messages via `{{ message.content }}` (Vue
    # auto-escape — XSS bloqueado no rendering). Esse helper blinda contra
    # regressão futura caso alguém troque pra `v-html`, e também limpa nomes
    # com control chars que quebrariam a pílula visual. Não escapa &, ", '
    # pra preservar nomes legítimos como "Maria d'Aragão" ou "Pedro & João".
    def safe_label(text)
      return nil if text.nil?

      text.to_s
          .delete("\x00")
          .gsub(/[[:cntrl:]]/, ' ')
          .gsub(/[<>]/, '')
          .squeeze(' ')
          .strip[0, 120].to_s.presence
    end
  end
end
