# Pipeline B — orquestra resposta da Bea quando @beatriz é mencionada
# no Chat Interno. Pipeline propositalmente enxuto:
#
#   1. Carrega contexto (mensagem original + últimas N msgs da sala
#      + mensagem citada se há reply).
#   2. Monta prompt com SystemPrompt + contexto.
#   3. Chama LLM com Toolset reduzido (read-only, sem book/cancel).
#   4. Posta resposta como Bea via InternalChat::MessageDispatcher,
#      com `in_reply_to` apontando pra mensagem original.
#
# Sem state machine, sem patient memory, sem follow-ups, sem sentinel —
# essa é uma conversa profissional simples, não um atendimento clínico.
#
# Spec: docs/01-product/ai-agent-configuration-plan.md (Apêndice F.3)
class AiAgent::InternalChat::Responder
  HISTORY_LIMIT = 10
  RATE_LIMIT_REPLY = 'Cheguei no meu limite de mensagens deste canal por hoje. Pra continuar, falem direto entre vocês — amanhã eu volto. 🙏'.freeze
  ERROR_REPLY = 'Tive um problema pra processar agora. Tentem em alguns minutos.'.freeze

  def self.respond(message_id:, account_id: nil)
    new(message_id, account_id: account_id).respond
  end

  def initialize(message_id, account_id: nil)
    @message_id = message_id
    @expected_account_id = account_id
  end

  def respond
    message = ::InternalChat::Message.find_by(id: @message_id)
    return unless message
    return if message.content_type == 'system'

    room = message.room
    account = room.account

    # Defesa cross-tenant: se o job foi enfileirado com account_id
    # esperado (caminho normal via AiAgentMentionListener), checa que
    # a mensagem realmente pertence a essa conta. Bloqueia jobs forjados
    # com message_id de outra conta.
    if @expected_account_id && account&.id != @expected_account_id.to_i
      Rails.logger.warn(
        '[AiAgent::InternalChat::Responder] account mismatch: ' \
        "message_id=#{@message_id} expected=#{@expected_account_id} actual=#{account&.id}"
      )
      return
    end

    bea = ::InternalChat::BeaResolver.for_account(account)
    return unless bea

    # Loop guard — Bea nunca responde a mensagem cujo sender é AI (ela
    # mesma ou outra IA futura). Evita loops infinitos.
    return if message.sender_ai_agent_id.present?

    # Confirma que a mensagem realmente menciona Bea (defesa: o listener
    # já filtra, mas se chamado direto via runner/job, validamos aqui).
    return unless message_mentions?(message, bea)

    rate_status = AiAgent::InternalChat::RateLimiter.check(room: room, bea: bea)
    return post_rate_limit_notice(room, bea, message) if !rate_status.allowed && rate_status.first_block?
    return unless rate_status.allowed

    body = generate_response(account, room, message, bea)
    return if body.blank?

    post_reply(room, bea, message, body)
  rescue StandardError => e
    Rails.logger.error(
      "[AiAgent::InternalChat::Responder] message_id=#{@message_id} falhou: #{e.class}: #{e.message}"
    )
    post_error_reply(room, bea, message) if defined?(room) && defined?(bea) && defined?(message)
  end

  private

  def message_mentions?(message, bea)
    # Lê da tabela `internal_chat_mentions` (fonte de verdade) em vez do
    # `content_attributes['mentioned_ai_agent_ids']`. Importante porque o
    # MentionExtractor adiciona menção implícita quando o reply aponta pra
    # msg de IA — o content_attributes não reflete isso, mas a Mention é
    # criada normalmente.
    message.mentions.exists?(ai_agent_id: bea.id)
  end

  def generate_response(account, room, message, bea)
    # Idempotente; carrega keys do InstallationConfig pra RubyLLM.config
    # se ainda não foi feito (ex: primeira chamada após boot do Sidekiq).
    ::Llm::Config.initialize! if defined?(::Llm::Config)

    history = build_history(room, message, bea)
    prompt = build_prompt(history, message)

    chat = ::RubyLLM.chat(model: model_for_account(account))
    chat.with_instructions(AiAgent::InternalChat::SystemPrompt.resolve)

    # SEC-12: propaga o user que mencionou Bea pros tools privilegiados.
    # `message.sender` retorna User quando sender_user_id presente, nil
    # quando é AI (Bea mesmo respondendo a outra IA, etc) — tools tratam
    # nil como "sem invocador humano" e bloqueiam por padrão.
    AiAgent::InternalChat::Toolset
      .tools_for(account, invoking_user: message.sender)
      .each { |t| chat.with_tool(t) }

    response = chat.ask(prompt)
    record_usage(account, response)
    response.content.to_s.strip
  end

  def build_history(room, message, bea)
    # Últimas N msgs visíveis da sala, em ordem cronológica, excluindo
    # mensagens de sistema e a própria mensagem atual.
    room.messages
        .visible
        .where.not(content_type: 'system')
        .where('id < ?', message.id)
        .order(id: :desc)
        .limit(HISTORY_LIMIT)
        .reverse
        .map { |m| { speaker: speaker_label(m, bea), content: m.content.to_s.strip } }
        .reject { |h| h[:content].empty? }
  end

  def speaker_label(msg, bea)
    return 'Você (Beatriz)' if msg.sender_ai_agent_id == bea.id
    return msg.sender&.available_name || 'Membro' if msg.sender_user_id

    'Sistema'
  end

  def build_prompt(history, message)
    author = message.sender&.available_name || 'Alguém'
    replied = replied_message_for(message)

    sections = []
    if history.any?
      formatted_history = history.map { |h| "#{h[:speaker]}: #{h[:content]}" }.join("\n")
      sections << "Histórico recente da sala (últimas #{history.size} msgs):\n#{formatted_history}"
    end

    sections << "Mensagem que está sendo respondida:\n#{replied.sender&.available_name || 'Alguém'}: #{replied.content.to_s.strip}" if replied

    sections << "#{author} mencionou você agora:\n#{message.content.to_s.strip}"
    sections.join("\n\n")
  end

  def replied_message_for(message)
    in_reply_to = (message.content_attributes || {})['in_reply_to']
    return nil unless in_reply_to

    # Scope pra mesma sala — bloqueia injection cross-room/cross-tenant
    # via `content_attributes['in_reply_to']` apontando pra msg de outra
    # conta. Sem isso, Bea poderia incluir conteúdo cross-tenant no prompt
    # e ecoar na resposta.
    message.room.messages.find_by(id: in_reply_to)
  end

  def model_for_account(_account)
    provider = (::InstallationConfig.find_by(name: 'CAPTAIN_LLM_PROVIDER')&.value || 'openai').to_s
    case provider
    when 'gemini'
      ::InstallationConfig.find_by(name: 'CAPTAIN_GEMINI_MODEL')&.value.presence || 'gemini-2.5-flash'
    else
      ::InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_MODEL')&.value.presence || 'gpt-4o-mini'
    end
  end

  def record_usage(account, response)
    return unless defined?(::AiAgent::UsageCounter)

    AiAgent::UsageCounter.bump!(
      account_id: account.id,
      input_tokens: response.input_tokens.to_i,
      output_tokens: response.output_tokens.to_i,
      cost_cents: 0,
      conversations: 0
    )
  rescue StandardError => e
    Rails.logger.warn("[AiAgent::InternalChat::Responder] usage counter falhou: #{e.message}")
  end

  def post_reply(room, bea, original_message, body)
    ::InternalChat::MessageDispatcher.call(
      room: room,
      sender: bea,
      content: body,
      content_attributes: {
        'in_reply_to' => original_message.id,
        'pipeline' => 'internal_chat_response'
      }
    )
  end

  def post_rate_limit_notice(room, bea, original_message)
    ::InternalChat::MessageDispatcher.call(
      room: room,
      sender: bea,
      content: RATE_LIMIT_REPLY,
      content_attributes: {
        'in_reply_to' => original_message.id,
        'pipeline' => 'internal_chat_rate_limit'
      }
    )
  end

  def post_error_reply(room, bea, original_message)
    ::InternalChat::MessageDispatcher.call(
      room: room,
      sender: bea,
      content: ERROR_REPLY,
      content_attributes: {
        'in_reply_to' => original_message.id,
        'pipeline' => 'internal_chat_error'
      }
    )
  rescue StandardError => e
    Rails.logger.error("[AiAgent::InternalChat::Responder] post_error_reply falhou: #{e.message}")
  end
end
