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

    def text
      a = @actor&.available_name || 'Sistema'
      t = @target&.available_name
      case @event
      when :member_added then "#{a} adicionou #{t} ao grupo"
      when :member_removed then "#{a} removeu #{t} do grupo"
      when :member_left then "#{t || a} saiu do grupo"
      when :role_changed then "#{a} definiu #{t} como #{@payload[:role]}"
      when :renamed then "#{a} renomeou o grupo para “#{@payload[:name]}”"
      when :description_changed then "#{a} alterou a descrição do grupo"
      end
    end
  end
end
