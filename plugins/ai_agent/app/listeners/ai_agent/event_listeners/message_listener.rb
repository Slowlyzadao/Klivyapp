module AiAgent
  module EventListeners
    # Listens to Chatwoot `message_created` events. When an inbound message
    # arrives in a conversation that belongs to a Bea-enabled account, we
    # enqueue ChatResponseJob to draft and post the reply asynchronously.
    #
    # Defensive filters (in order of cheapness):
    #   1. message must be incoming (from contact, not agent)
    #   2. sender must be a real Contact (não outro bot, API externa, etc.)
    #   3. account must have Bea enabled
    #   4. message's inbox must be linked to Beatriz (Captain::Inbox)
    #   5. conversation must not be already escalated
    #   6. conversation must not have a human assignee
    class MessageListener < ::BaseListener
      include Singleton

      # Wait buffer: pacientes em WhatsApp normalmente fragmentam o
      # raciocínio em várias mensagens curtas em sequência (ex:
      # "Gabriel Fernandes Correia" + "tem 14 anos" + "é menor"). Sem
      # delay, a Bea responde a primeira antes da segunda chegar e o
      # contexto fica quebrado. Atrasamos a execução por N segundos;
      # se outra incoming chegar nesse intervalo, o ChatResponseJob da
      # primeira detecta a mais nova e pula (a mais nova vai responder
      # cobrindo todo o burst).
      #
      # 3s = sweet spot. Curto o bastante pra parecer natural, longo o
      # bastante pra absorver o digitar+enviar de uma 2ª mensagem.
      DEBOUNCE_SECONDS = 3

      def message_created(event)
        message = event.data[:message]
        return unless should_handle?(message)

        # Subscribed via SyncDispatcher → this runs inside the Message's
        # after_create_commit callback chain. Any exception here bubbles up
        # and breaks the message persistence, so wrap defensively.
        begin
          rl = AiAgent::RateLimiter.new(
            account_id: message.account_id,
            conversation_id: message.conversation.id
          ).check_and_increment

          unless rl.allowed?
            Rails.logger.warn("[AiAgent] rate limited: #{rl.reason} (msg=#{message.id})")
            return
          end

          AiAgent::ChatResponseJob.set(wait: DEBOUNCE_SECONDS.seconds).perform_later(message.id)
        rescue StandardError => e
          # Most likely a Redis hiccup on enqueue. Log and move on; the inbox
          # message itself stays intact, the user just doesn't get a Bea reply
          # to this turn.
          Rails.logger.error(
            "[AiAgent::MessageListener] failed to enqueue Bea for msg #{message.id}: #{e.class}: #{e.message}"
          )
        end
      end

      private

      def should_handle?(message)
        return false unless message.incoming?
        return false unless from_real_contact?(message)
        return false if message.private?
        return false if sent_via_api?(message)
        # Mensagem só com mídia (áudio do WhatsApp PTT, foto, vídeo,
        # documento) chega com content vazio — nesse caso ainda
        # queremos processar pra Sprint F (transcrição) / F2
        # (classificação de imagem). Só pula se NÃO houver nem
        # texto NEM attachment processável.
        return false if message.content.to_s.strip.empty? && !has_processable_attachment?(message)

        account = message.account
        setting = account.ai_agent_setting
        return false unless setting&.enabled

        # The inbox where the message landed must be explicitly linked to
        # Beatriz on the assistant's "Caixas de entrada" tab. If she's not
        # connected to this inbox, Bea doesn't even queue a job for it —
        # the conversation is treated as if Bea didn't exist.
        return false unless beatriz_linked_to_inbox?(account, message.inbox_id)

        conversation = message.conversation
        state = AiAgent::ConversationState.find_by(
          account_id: account.id,
          conversation_id: conversation.id
        )
        return false if state&.status == 'escalated'

        # Skip if a human is actively handling this conversation.
        return false if conversation.assignee_id.present?

        true
      end

      # Mensagem só vale resposta da Bea se o emissor for um Contact (paciente).
      # Mensagens "incoming" criadas por integração externa (n8n, webhook,
      # bot legacy do Captain, AgentBot) podem cair com sender_type diferente
      # ou nil — nesses casos a Bea NÃO deve responder, sob risco de loop
      # de bots conversando entre si. Checamos a coluna direto pra não
      # carregar a association.
      def from_real_contact?(message)
        message.sender_type == 'Contact' && message.sender_id.present?
      end

      # Mensagens criadas via API externa (integração marketing, broadcast,
      # n8n posando como inbound) trazem essa flag em content_attributes.
      # Bea não responde a essas — quem manda já tem sua própria lógica.
      def sent_via_api?(message)
        message.content_attributes.is_a?(Hash) && message.content_attributes['sent_via_api'] == true
      end

      # Tipos de attachment que a Bea sabe processar via Sprint F/F2.
      # Outros (location, share, story_mention, etc) não disparam o job.
      PROCESSABLE_ATTACHMENT_TYPES = %w[audio image video file].freeze

      def has_processable_attachment?(message)
        return false if message.attachments.blank?

        message.attachments.any? { |a| PROCESSABLE_ATTACHMENT_TYPES.include?(a.file_type.to_s) }
      end

      def beatriz_linked_to_inbox?(account, inbox_id)
        return false if inbox_id.blank?
        return false unless defined?(::Captain::Assistant) && defined?(::CaptainInbox)

        beatriz = ::Captain::Assistant.where(account_id: account.id, name: 'Beatriz').first
        return false if beatriz.nil?

        ::CaptainInbox.exists?(captain_assistant_id: beatriz.id, inbox_id: inbox_id)
      end
    end
  end
end
