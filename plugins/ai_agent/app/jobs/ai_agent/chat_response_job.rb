module AiAgent
  # Async worker for one conversation turn.
  # Reads recent history from Chatwoot, calls ChatService, posts the reply
  # back to the conversation as an outgoing message owned by the Bea AgentBot.
  class ChatResponseJob < ApplicationJob
    include ::Events::Types

    queue_as :default

    # Disable Sidekiq's automatic retry. The ChatService already has its own
    # in-process retry for transient provider errors (Gemini "high demand"),
    # and re-running the whole job after a partial success would post a
    # duplicate reply to the patient — we've seen this happen repeatedly
    # under Gemini free-tier rate limits.
    sidekiq_options retry: 0

    HISTORY_LIMIT = 10
    HISTORY_TTL_HOURS = 24
    # Race condition: WhatsApp dispara `Message.after_create_commit`
    # antes do upload do blob de áudio/imagem terminar no storage.
    # Reenfileiramos o job com delay quando isso acontece. 3 tentativas
    # totais (cada uma + retry interno do AudioTranscriber) cobrem
    # blobs grandes (≈30s no pior caso).
    MAX_BLOB_RETRY = 3
    BLOB_RETRY_DELAY = 5.seconds

    def perform(message_id, attempt: 1)
      message = Message.find_by(id: message_id)
      return unless message

      # Coalescing: se chegou uma mensagem incoming MAIS NOVA na mesma
      # conversa, esta perdeu a corrida — o job da mais nova vai
      # responder por todas (a history dela inclui esta). Pular evita
      # respostas fragmentadas (Bea respondendo "Gabriel Fernandes
      # Correia" e depois respondendo de novo "tem 14 anos"). Casa com
      # o `wait` de 3s do MessageListener.
      newer_incoming = Message
                       .where(conversation_id: message.conversation_id)
                       .where(message_type: :incoming)
                       .where('id > ?', message.id)
                       .where(private: false)
                       .exists?
      if newer_incoming
        Rails.logger.info("[AiAgent::ChatResponseJob] msg #{message.id} superada por incoming mais nova — pulando (a mais nova vai responder)")
        return
      end

      # Idempotência forte: se já existe Trace bem-sucedido (error_message
      # nil) pra esta message_id específica, pula. O índice único parcial
      # garante que isso não falha em race: dois jobs simultâneos vão um
      # criar e o outro receber RecordNotUnique no persist_trace (tratado
      # como DuplicateTurnError pelo rescue lá embaixo).
      if AiAgent::Trace.where(message_id: message.id, error_message: nil).exists?
        Rails.logger.info("[AiAgent::ChatResponseJob] msg #{message.id} já tem Trace — pulando duplicata")
        return
      end

      conversation = message.conversation
      account = message.account

      typing_on(conversation)

      # Sprint F2: imagem/vídeo. Antes de tudo, se a mensagem é
      # primariamente uma mídia visual, classifica e escala humano —
      # CFM proíbe Bea interpretar conteúdo médico de imagem.
      if (visual = first_visual_attachment(message))
        handle_visual(conversation, message.inbox, visual)
        return
      end

      # Sprint F MVP: voice notes. Se a mensagem chega como áudio
      # (WhatsApp PTT), transcreve via Whisper antes de mandar pro
      # ChatService. Texto da transcrição é "como se" o paciente
      # tivesse digitado — fluxo normal de Bea (state machine,
      # emergency, tools, sentinel) roda igual.
      effective_content = resolve_message_content(message, conversation)

      # Race condition: blob ainda não chegou ao storage. Reenfileira
      # com delay até MAX_BLOB_RETRY antes de cair no fallback.
      if effective_content == :file_not_ready
        if attempt < MAX_BLOB_RETRY
          Rails.logger.info("[AiAgent::ChatResponseJob] msg #{message.id} blob não pronto, reenfileirando (tentativa #{attempt + 1}/#{MAX_BLOB_RETRY})")
          self.class.set(wait: BLOB_RETRY_DELAY).perform_later(message_id, attempt: attempt + 1)
          return
        end
        Rails.logger.warn("[AiAgent::ChatResponseJob] msg #{message.id} blob ainda não pronto após #{MAX_BLOB_RETRY} tentativas — fallback")
        post_audio_fallback(conversation, message.inbox)
        return
      end

      if effective_content.blank?
        post_audio_fallback(conversation, message.inbox)
        return
      end

      history = build_history(conversation, message)

      result = AiAgent::ChatService.new(
        account: account,
        conversation_id: conversation.id,
        contact_id: conversation.contact_id,
        history: history
      ).respond(effective_content, message_id: message.id)

      post_reply(conversation, message.inbox, result.message) if result.message.present?

      # Toda resposta da Bea (não só handoff) precisa promover a conversa
      # de `pending` para `open` no Chatwoot. Conversas em pending são
      # invisíveis na aba "Abertas" — sem este passo, mesmo respondendo
      # a paciente fica enxergando a Bea responder no WhatsApp mas o
      # atendente humano não vê o histórico no dashboard.
      promote_to_open(conversation) if result.message.present? && conversation.pending?

      handle_handoff(conversation) if result.handoff
    rescue AiAgent::ChatService::BeaDisabledError, AiAgent::ChatService::BudgetExceededError => e
      Rails.logger.warn("[AiAgent] skip reply: #{e.message}")
    rescue AiAgent::ChatService::DuplicateTurnError => e
      # Outro job ganhou a corrida e já gravou Trace. Não retentar.
      Rails.logger.info("[AiAgent::ChatResponseJob] #{e.message} (msg=#{message_id})")
    rescue StandardError => e
      Rails.logger.error("[AiAgent::ChatResponseJob] #{e.class}: #{e.message}")
      raise
    ensure
      typing_off(conversation) if conversation
    end

    private

    # Memória per-contato com janela de 24h. Atravessa múltiplas
    # conversas do mesmo Contact — se o paciente abrir conversa nova
    # dentro de 24h da anterior, Bea ainda lembra o contexto. Quando
    # o Contact é deletado no Chatwoot, conversas e mensagens
    # cascateiam, então o histórico some junto (sem state nosso).
    # Fallback pra histórico só da conv atual quando o contato é
    # anônimo (sem contact_id — caso raro de inbox sem identificação).
    def build_history(conversation, current_message)
      if conversation.contact_id.present?
        AiAgent::Memory::CrossConversationHistory.new(
          account_id: conversation.account_id,
          contact_id: conversation.contact_id,
          current_message: current_message,
          limit: HISTORY_LIMIT,
          ttl_hours: HISTORY_TTL_HOURS
        ).build
      else
        # `Message.default_scope` ordena ASC e sobrescreve `.order(:desc)`.
        # `reorder` força DESC pra que o LIMIT pegue as N mais recentes,
        # depois inverte pra cronológico (LLM precisa ler oldest→newest).
        conversation.messages
                    .where(message_type: %i[incoming outgoing])
                    .where('id < ?', current_message.id)
                    .where(private: false)
                    .reorder(created_at: :desc, id: :desc)
                    .limit(HISTORY_LIMIT)
                    .to_a
                    .reverse
                    .map { |m| { role: m.incoming? ? 'user' : 'assistant', content: m.content.to_s } }
      end
    end

    # Decide qual texto vai pro ChatService. Se a mensagem tem texto
    # já, usa direto. Se for só áudio, tenta transcrever via Whisper
    # e persiste a transcrição em `message.content` pra que histórico
    # e dashboard mostrem o que foi dito (o blob de áudio fica como
    # attachment normal). Se transcrição falhar, retorna nil pra que
    # o caller poste um fallback determinístico ao paciente.
    def resolve_message_content(message, conversation)
      content = message.content.to_s.strip
      return content if content.present?

      audio = message.attachments.find { |a| a.file_type.to_s == 'audio' }
      return content if audio.nil?

      result = AiAgent::Multimodal::AudioTranscriber.new(attachment: audio).call

      # Sentinel especial: blob ainda não chegou ao storage. Caller
      # reenfileira o job em vez de cair no fallback.
      return :file_not_ready if result == AiAgent::Multimodal::AudioTranscriber::FILE_NOT_READY
      return nil if result.nil? || result.text.blank?

      # Salva a transcrição na mensagem (silent update — não dispara
      # nova trigger de listener porque o listener filtra por
      # incoming sem content só quando já não foi processado).
      message.update_columns(content: result.text)
      Rails.logger.info("[AiAgent] audio transcrito msg=#{message.id} chars=#{result.text.length}")
      result.text
    end

    # Mídia visual: imagem ou vídeo. Texto curto que veio junto da
    # imagem (ex: "olha aqui a receita") é ignorado nesta versão —
    # qualquer mídia visual já dispara handoff. Em F3 podemos juntar
    # texto + imagem ao classificar.
    def first_visual_attachment(message)
      message.attachments.find { |a| %w[image video].include?(a.file_type.to_s) }
    end

    def handle_visual(conversation, inbox, attachment)
      result = if attachment.file_type.to_s == 'video'
                 AiAgent::Multimodal::ImageHandler.video_result
               else
                 AiAgent::Multimodal::ImageHandler.new(attachment: attachment).call
               end

      # Nota interna pra equipe (não visível ao paciente).
      conversation.messages.create!(
        message_type: :outgoing,
        account_id: conversation.account_id,
        inbox_id: inbox.id,
        sender: AiAgent::AgentBotIdentity.ensure!,
        private: true,
        content: result.staff_note
      )

      # Mensagem pro paciente.
      conversation.messages.create!(
        message_type: :outgoing,
        account_id: conversation.account_id,
        inbox_id: inbox.id,
        sender: AiAgent::AgentBotIdentity.ensure!,
        content: result.patient_message
      )

      # Handoff: tira do bot, vai pro humano. Mesmo padrão de
      # `handle_handoff` mas sem a mensagem privada genérica
      # (já postamos uma nota específica acima).
      promote_to_open(conversation) if conversation.pending?
      Rails.logger.info("[AiAgent::ChatResponseJob] visual handoff conv=#{conversation.id} category=#{result.category} attachment=#{attachment.id}")
    end

    def post_audio_fallback(conversation, inbox)
      conversation.messages.create!(
        message_type: :outgoing,
        account_id: conversation.account_id,
        inbox_id: inbox.id,
        sender: AiAgent::AgentBotIdentity.ensure!,
        content: 'Recebi seu áudio mas não consegui ouvi-lo bem por aqui. Você pode me mandar a mensagem por escrito? 🎙️'
      )
      promote_to_open(conversation) if conversation.pending?
    end

    def post_reply(conversation, inbox, content)
      conversation.messages.create!(
        message_type: :outgoing,
        account_id: conversation.account_id,
        inbox_id: inbox.id,
        sender: AiAgent::AgentBotIdentity.ensure!,
        content: content
      )
    end

    # Move uma conversa de `pending` (estado do bot) para `open` (visível
    # no inbox do atendente). `bot_handoff!` é o caminho canônico do
    # Chatwoot — também dispara CONVERSATION_BOT_HANDOFF que outros
    # listeners (notificações, SLA) consomem. Fallback pra update direto
    # caso o método não exista. Best-effort: log e segue se falhar, não
    # vamos perder a resposta por causa de mudança de status.
    def promote_to_open(conversation)
      if conversation.respond_to?(:bot_handoff!)
        conversation.bot_handoff!
      else
        conversation.update(status: :open)
      end
    rescue StandardError => e
      Rails.logger.warn("[AiAgent] promote_to_open falhou conv=#{conversation.id}: #{e.message}")
    end

    # Typing indicator has two layers:
    #   1. Chatwoot ActionCable event (for the dashboard inbox UI)
    #   2. WhatsApp presence update (so the patient's phone shows "digitando…")
    #
    # The Chatwoot dispatch is best-effort — AgentBot has no `pubsub_token`,
    # so it fails silently in ActionCableListener, which is fine.
    # The WhatsApp side is the one the patient actually sees.
    def typing_on(conversation)
      dispatch_chatwoot_typing(conversation, CONVERSATION_TYPING_ON)
      send_whatsapp_presence(conversation, 'composing')
    end

    def typing_off(conversation)
      dispatch_chatwoot_typing(conversation, CONVERSATION_TYPING_OFF)
      send_whatsapp_presence(conversation, 'paused')
    end

    def dispatch_chatwoot_typing(conversation, event)
      Rails.configuration.dispatcher.dispatch(
        event,
        Time.zone.now,
        conversation: conversation,
        user: AiAgent::AgentBotIdentity.ensure!,
        is_private: false
      )
    rescue StandardError => e
      Rails.logger.debug { "[AiAgent] typing dispatch skipped: #{e.message}" }
    end

    WHATSAPP_BRIDGE_URL = ENV.fetch('WHATSAPP_QR_BRIDGE_URL') { ENV.fetch('WHATSAPP_BRIDGE_URL', 'http://localhost:3002') }

    # Hits the WhatsApp bridge so the patient sees "digitando..." while Bea
    # is working on the reply (~2-5s). Only fires for whatsapp_qr inboxes
    # (Baileys); cloud/360 channels would need their own integration.
    # Best-effort with very short timeouts — we never want a flaky bridge to
    # delay or break the actual reply pipeline.
    def send_whatsapp_presence(conversation, state)
      inbox = conversation.inbox
      return unless inbox&.channel_type == 'Channel::Whatsapp'
      return unless inbox.channel.respond_to?(:provider) && inbox.channel.provider.to_s == 'whatsapp_qr'

      contact = conversation.contact
      phone = contact&.phone_number.to_s.gsub(/\D/, '')
      return if phone.empty?

      uri = URI("#{WHATSAPP_BRIDGE_URL}/sessions/#{inbox.id}/presence")
      http = Net::HTTP.new(uri.host, uri.port)
      http.open_timeout = 2
      http.read_timeout = 3
      req = Net::HTTP::Post.new(uri, 'Content-Type' => 'application/json')
      req.body = { to: "#{phone}@s.whatsapp.net", state: state }.to_json
      http.request(req)
    rescue StandardError => e
      Rails.logger.debug { "[AiAgent] whatsapp presence (#{state}) skipped: #{e.message}" }
    end

    # When Bea hands off, we (1) post a private note for the agent, and
    # (2) move the conversation from `pending` to `open` so it actually shows
    # up in the agent inbox. Without step 2 the convo stays under the bot's
    # responsibility in Chatwoot's eyes — invisible in the "Abertas" tab and
    # easy to miss completely. `bot_handoff!` is Chatwoot's canonical way to
    # do this; it also fires the CONVERSATION_BOT_HANDOFF event so any other
    # listener (notifications, SLA, etc.) reacts properly.
    def handle_handoff(conversation)
      conversation.messages.create!(
        message_type: :outgoing,
        account_id: conversation.account_id,
        inbox_id: conversation.inbox_id,
        sender: AiAgent::AgentBotIdentity.ensure!,
        private: true,
        content: '⚠️ Bea transferiu esta conversa para atendimento humano.'
      )

      if conversation.respond_to?(:bot_handoff!) && conversation.pending?
        conversation.bot_handoff!
      elsif conversation.pending?
        conversation.update(status: :open)
      end
    end
  end
end
