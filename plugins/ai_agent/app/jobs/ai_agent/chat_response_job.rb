# Async worker for one conversation turn.
# Reads recent history from Chatwoot, calls ChatService, posts the reply
# back to the conversation as an outgoing message owned by the Bea AgentBot.
class AiAgent::ChatResponseJob < ApplicationJob
  include ::Events::Types

  queue_as :default

  # Disable Sidekiq's automatic retry. The ChatService already has its own
  # in-process retry for transient provider errors (Gemini "high demand"),
  # and re-running the whole job after a partial success would post a
  # duplicate reply to the patient — we've seen this happen repeatedly
  # under Gemini free-tier rate limits.
  sidekiq_options retry: 0

  # 40 MENSAGENS, não turnos: cada bolha da Bea é uma Message separada
  # (MessageChunker posta 2-3 por turno), então 10 mensagens ≈ só 3-4 turnos —
  # a resposta do paciente saía da janela no meio do agendamento e a Bea
  # "esquecia" (ex.: re-perguntou "é pra você mesmo?" que o paciente já tinha
  # respondido por áudio). 40 ≈ 12-15 turnos, cobre um agendamento inteiro.
  HISTORY_LIMIT = 40
  HISTORY_TTL_HOURS = 24
  # Race condition: WhatsApp dispara `Message.after_create_commit`
  # antes do upload do blob de áudio/imagem terminar no storage.
  # Reenfileiramos o job com delay quando isso acontece. 3 tentativas
  # totais (cada uma + retry interno do AudioTranscriber) cobrem
  # blobs grandes (≈30s no pior caso).
  MAX_BLOB_RETRY = 3
  BLOB_RETRY_DELAY = 5.seconds

  # account_id é opcional pra compatibilidade com jobs já enfileirados
  # antes do MT-5 (auditoria 2026-05-18). Novos enqueues sempre passam
  # — MessageListener atualizado. Quando presente, validamos que a
  # mensagem realmente pertence a essa conta antes de processar.
  def perform(message_id, attempt: 1, account_id: nil)
    message = Message.find_by(id: message_id)
    return unless message

    # Defesa cross-tenant: se job foi enfileirado com account_id esperado,
    # checa que a mensagem ainda pertence a essa conta. Bloqueia jobs
    # forjados com message_id de outra conta + protege contra race se
    # conversa for reatribuída entre enqueue e perform.
    if account_id && message.account_id != account_id.to_i
      Rails.logger.warn(
        '[AiAgent::ChatResponseJob] account mismatch: ' \
        "message_id=#{message_id} expected=#{account_id} actual=#{message.account_id}"
      )
      return
    end

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
                     .exists?(private: false)
    if newer_incoming
      Rails.logger.info("[AiAgent::ChatResponseJob] msg #{message.id} superada por incoming mais nova — pulando (a mais nova vai responder)")
      return
    end

    # Idempotência forte: se já existe Trace bem-sucedido (error_message
    # nil) pra esta message_id específica, pula. O índice único parcial
    # garante que isso não falha em race: dois jobs simultâneos vão um
    # criar e o outro receber RecordNotUnique no persist_trace (tratado
    # como DuplicateTurnError pelo rescue lá embaixo).
    if AiAgent::Trace.exists?(message_id: message.id, error_message: nil)
      Rails.logger.info("[AiAgent::ChatResponseJob] msg #{message.id} já tem Trace — pulando duplicata")
      return
    end

    conversation = message.conversation
    account = message.account

    # Gate de TESTE: quando CAPTAIN_BEA_PHONE_ALLOWLIST está setado, a Bea SÓ
    # responde os números dessa lista. Vazio/ausente = responde todos
    # (produção). Evita a Bea responder contatos de teste/terceiros.
    unless phone_allowed?(conversation)
      Rails.logger.info("[AiAgent::ChatResponseJob] msg #{message.id} ignorada: contato fora da allowlist de testes")
      return
    end

    # Gate de LANÇAMENTO (modo voucher): a Bea SÓ responde quem chegou por
    # voucher — a FOTO do voucher OU um dos textos-gatilho do QR. Quem chega de
    # outro jeito fica sem resposta nenhuma (nem "digitando"). Conversa já
    # ativada por voucher continua sendo atendida nos próximos turnos.
    voucher_gate = AiAgent::Voucher::Gate.new(account: account, conversation: conversation, message: message)
    if voucher_gate.enabled? && !voucher_gate.allowed?
      Rails.logger.info("[AiAgent::ChatResponseJob] msg #{message.id} ignorada: modo voucher, sem voucher/gatilho")
      return
    end

    typing_on(conversation)

    # Imagem/vídeo. FORA do modo voucher (ou vídeo): classifica e escala humano
    # (CFM proíbe Bea interpretar conteúdo clínico de imagem). NO modo voucher,
    # uma IMAGEM é o voucher → lê o texto (OCR) e segue o fluxo, sem handoff.
    if (visual = first_visual_attachment(message))
      if voucher_gate.enabled? && visual.file_type.to_s == 'image'
        effective_content = handle_voucher_image(message, conversation, visual, attempt, account_id, voucher_gate)
        # nil = já tratado (reenfileirado ou já pedimos pra reenviar) → encerra.
        return if effective_content.blank?
      else
        handle_visual(conversation, message.inbox, visual)
        return
      end
    else
      # Voice notes: transcreve via Whisper; texto vira "como se" digitado.
      effective_content = resolve_message_content(message, conversation)

      # Race condition: blob ainda não chegou ao storage. Reenfileira com
      # delay até MAX_BLOB_RETRY antes de cair no fallback.
      if effective_content == :file_not_ready
        if attempt < MAX_BLOB_RETRY
          Rails.logger.info("[AiAgent::ChatResponseJob] msg #{message.id} blob não pronto, reenfileirando (tentativa #{attempt + 1}/#{MAX_BLOB_RETRY})")
          self.class.set(wait: BLOB_RETRY_DELAY).perform_later(
            message_id, attempt: attempt + 1, account_id: account_id || message.account_id
          )
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

      # Modo voucher ativado por TEXTO-gatilho: marca a conversa pra seguir
      # respondendo nos próximos turnos (a imagem marca dentro do OCR).
      voucher_gate.mark_activated! if voucher_gate.enabled? && !voucher_gate.activated?
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
  # Allowlist de telefones pra TESTE. Lê CAPTAIN_BEA_PHONE_ALLOWLIST
  # (InstallationConfig): números separados por vírgula/espaço. Vazio = sem
  # restrição (produção). Match pelos 8 últimos dígitos (parte invariante do
  # número BR), contra o telefone do contato OU o source_id do contact_inbox.
  def phone_allowed?(conversation)
    raw = ::InstallationConfig.find_by(name: 'CAPTAIN_BEA_PHONE_ALLOWLIST')&.value.to_s
    allowed = raw.split(/[,;\s]+/).filter_map { |n| d = n.gsub(/\D/, ''); d.last(8) if d.present? }
    return true if allowed.empty?

    candidates = [conversation.contact&.phone_number, conversation.contact_inbox&.source_id]
                 .compact.filter_map { |v| d = v.to_s.gsub(/\D/, ''); d.last(8) if d.present? }
    (candidates & allowed).any?
  end

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
  def resolve_message_content(message, _conversation)
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

    # Nota interna pra equipe (não visível ao paciente) — SÓ quando há
    # handoff (conteúdo clínico/documento). Saudação/social (greeting) não
    # gera nota nem escala: a Bea só responde com carinho.
    if result.handoff_required && result.staff_note.present?
      conversation.messages.create!(
        message_type: :outgoing,
        account_id: conversation.account_id,
        inbox_id: inbox.id,
        sender: AiAgent::AgentBotIdentity.ensure!,
        private: true,
        content: result.staff_note
      )
    end

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
    Rails.logger.info("[AiAgent::ChatResponseJob] visual conv=#{conversation.id} category=#{result.category} handoff=#{result.handoff_required} attachment=#{attachment.id}")
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

  # Modo voucher: lê a FOTO do voucher (OCR via Gemini) e devolve uma "mensagem
  # do paciente" sintetizada com o texto do voucher, pra Bea comemorar e
  # agendar. Retorna nil quando já tratou sozinho (reenfileirou o blob, ou
  # pediu pra reenviar) — aí o caller encerra. Marca a conversa como ativada.
  def handle_voucher_image(message, conversation, attachment, attempt, account_id, gate)
    result = AiAgent::Multimodal::VoucherTextExtractor.new(attachment: attachment).call

    if result == AiAgent::Multimodal::VoucherTextExtractor::FILE_NOT_READY
      if attempt < MAX_BLOB_RETRY
        Rails.logger.info("[AiAgent::ChatResponseJob] msg #{message.id} voucher blob não pronto, reenfileirando (#{attempt + 1}/#{MAX_BLOB_RETRY})")
        self.class.set(wait: BLOB_RETRY_DELAY).perform_later(message.id, attempt: attempt + 1, account_id: account_id || message.account_id)
        return nil
      end
      result = nil
    end

    # Marca ativada de qualquer jeito: mandar foto = intenção de voucher, então
    # ela segue podendo conversar por texto mesmo que o OCR falhe.
    gate.mark_activated!(voucher_text: result&.text)

    if result.nil? || !result.has_voucher
      post_voucher_help(conversation, message.inbox)
      return nil
    end

    Rails.logger.info("[AiAgent::ChatResponseJob] voucher lido conv=#{conversation.id}: #{result.text[0, 120].inspect}")
    "Oi! Acabei de enviar a foto do meu voucher. Nele está escrito: \"#{result.text}\""
  end

  def post_voucher_help(conversation, inbox)
    conversation.messages.create!(
      message_type: :outgoing,
      account_id: conversation.account_id,
      inbox_id: inbox.id,
      sender: AiAgent::AgentBotIdentity.ensure!,
      content: 'Aii, não consegui ler direitinho o seu voucher na foto 🙈 Me conta: qual desconto e qual procedimento está escrito nele?'
    )
    promote_to_open(conversation) if conversation.pending?
  end

  # Envia a resposta em BOLHAS separadas (parágrafos) em vez de um textão
  # único — mais humano. Entre bolhas: reativa "digitando..." e espera um
  # tempo proporcional ao tamanho do próximo bloco (simula digitação). O
  # `sleep` roda no worker do Sidekiq — ok, é resposta de baixo volume.
  def post_reply(conversation, inbox, content)
    chunks = AiAgent::MessageChunker.split(content)
    bot = AiAgent::AgentBotIdentity.ensure!

    chunks.each_with_index do |chunk, index|
      if index.positive?
        AiAgent::WhatsappPresence.push(@presence_target, AiAgent::WhatsappPresence::COMPOSING)
        sleep(AiAgent::MessageChunker.delay_for(chunk))
      end

      conversation.messages.create!(
        message_type: :outgoing,
        account_id: conversation.account_id,
        inbox_id: inbox.id,
        sender: bot,
        content: chunk
      )
    end
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
  #
  # RT-8 (auditoria 2026-05-18): aceito como limitação. Agente humano no
  # dashboard não vê "Bea está digitando..." porque AgentBot não tem
  # pubsub_token. Fix completo exigiria broadcast direto pra agents
  # atribuídos à conv (refactor médio do ActionCableListener pattern).
  # Pequeno valor — paciente vê via WhatsApp, agente vê msg ao chegar.
  TYPING_HEARTBEAT_INTERVAL = 8 # s — WhatsApp limpa o "digitando" sozinho em ~10s

  def typing_on(conversation)
    dispatch_chatwoot_typing(conversation, CONVERSATION_TYPING_ON)
    @presence_target = AiAgent::WhatsappPresence.target_for(conversation)
    AiAgent::WhatsappPresence.push(@presence_target, AiAgent::WhatsappPresence::COMPOSING)
    start_typing_heartbeat
  end

  def typing_off(conversation)
    stop_typing_heartbeat
    dispatch_chatwoot_typing(conversation, CONVERSATION_TYPING_OFF)
    AiAgent::WhatsappPresence.push(@presence_target, AiAgent::WhatsappPresence::PAUSED)
  end

  # Mantém o "digitando..." vivo enquanto a Bea pensa: o WhatsApp expira o
  # `composing` sozinho em ~10s, então reenviamos a cada TYPING_HEARTBEAT_INTERVAL.
  # Thread separada que só faz HTTP best-effort (não toca o banco — usa o
  # target já resolvido em primitivos), encerrada no typing_off (que roda no
  # `ensure` do perform, cobrindo todos os caminhos de retorno).
  def start_typing_heartbeat
    return if @presence_target.nil?

    @typing_heartbeat = Thread.new(@presence_target) do |target|
      loop do
        sleep TYPING_HEARTBEAT_INTERVAL
        AiAgent::WhatsappPresence.push(target, AiAgent::WhatsappPresence::COMPOSING)
      end
    rescue StandardError
      nil
    end
  end

  def stop_typing_heartbeat
    @typing_heartbeat&.kill
  ensure
    @typing_heartbeat = nil
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

  # `send_whatsapp_presence` foi extraído pra `AiAgent::WhatsappPresence`
  # (reutilizado pelo MessageListener pra disparar "digitando" na chegada).

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
