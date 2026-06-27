require 'ruby_llm'

# Gera o texto do follow-up usando o LLM leve (mesmo modelo do
# SentimentAnalyzer/Sentinel — gemini-flash ou gpt-4.1-mini).
#
# Recebe:
#   - rule           — FollowUpRule (traz `context_brief`)
#   - contact        — Chatwoot Contact
#   - agenda_event   — AgendaEvent (quando aplicável; nil em no_response)
#   - patient_memory — PatientMemory (preferences/history pra personalizar)
#
# Retorna `String` com a mensagem pronta pra postar — ou `nil` em
# falha. Caller (SendFollowUpJob) marca execution como `failed` e
# registra erro.
#
# Importante: NÃO usa o ChatService normal porque queremos:
#   1. Ignorar tools (essa msg é proativa, não deve agendar/cancelar)
#   2. Persona diferente — atendente proativa, não reativa
#   3. Custo baixo (modelo flash, 1 turn)
class AiAgent::FollowUps::MessageGenerator
  MAX_OUTPUT_TOKENS = 220
  DEFAULT_TIMEOUT = 12

  # Quantas mensagens recentes da conversa injetar como contexto.
  HISTORY_LIMIT = 8

  # Quantos trechos da base de conhecimento (RAG) injetar pra endereçar a
  # objeção do paciente no follow-up.
  MAX_KNOWLEDGE = 2

  # Tom base da Bea (PT-BR profissional, neutro, curto). A persona da
  # regra (Fase 5) é anexada a isso no `system_prompt`.
  BASE_PROMPT = <<~PROMPT.strip.freeze
    Você é a Bea, recepcionista virtual da clínica. Está enviando uma
    MENSAGEM PROATIVA pelo WhatsApp (paciente NÃO acabou de mandar
    mensagem — você está iniciando contato baseado num gatilho da clínica).

    Tom: profissional, próximo, NEUTRO regionalmente (sem gírias
    paulistas/cariocas — nada de "pô", "tô", "rola", "foi mal", "tipo").
    Use no máximo 3 frases. Pode usar 1 emoji se fizer sentido (✅
    confirmação, ❤️ acolhimento). Nunca emoji robótico (👋, 🙂, 😊).

    Personalize com o nome do paciente quando disponível. Se houver uma
    consulta envolvida, mencione data, hora e profissional. Se houver
    HISTÓRICO da conversa, dê continuidade natural (não repita o que já
    foi dito). Se o cenário pedir uma resposta (ex: confirmação), deixe a
    pergunta clara e direta.

    IMPORTANTE — leia o HISTÓRICO: se o paciente levantou uma OBJEÇÃO ou
    dúvida concreta (preço/"não tenho dinheiro", medo, falta de tempo,
    indecisão, "vou pensar", "preciso falar com alguém"), o follow-up deve
    ENDEREÇAR isso diretamente e com acolhimento — usando as INFORMAÇÕES DA
    CLÍNICA fornecidas abaixo (ex.: opções de parcelamento) pra ajudar a
    superar a objeção. NÃO mande um "ficou alguma dúvida?" genérico que
    ignora o que o paciente acabou de dizer.

    NUNCA invente data, hora, profissional, valor ou dado clínico que não
    esteja no contexto fornecido (incluindo as informações da clínica
    abaixo). Se algo essencial faltar, escreva mensagem genérica de check-in.
  PROMPT

  # SEC-25 (auditoria 2026-05-18): hard cap pra output do LLM antes de
  # enviar ao paciente. WhatsApp recomenda <1000 chars; 800 deixa folga
  # pra emoji + saudação sem corte abrupto. Outputs maiores indicam LLM
  # alucinando (ex: recitando system prompt) — descarta como sinal.
  MAX_OUTPUT_CHARS = 800

  # SEC-25: padrões que indicam LLM saiu do papel — JSON, código,
  # markdown estruturado, system prompt eco. Cada um é red flag separado.
  STRUCTURED_OUTPUT_PATTERNS = [
    /\A\s*[{\[]/,                # JSON open
    /\A\s*```/,                  # markdown code fence
    /\A\s*<[a-z]+[\s>]/i,        # HTML/XML
    /^\s*"\w+"\s*:/,             # JSON key
    /^\s*(function|def|class)\s/, # code definition
    # Eco do system prompt: ANCORADO no início + específico ("Você é a Bea,
    # recepcionista..."). O padrão antigo `/Você é (a|o) /i` (sem âncora)
    # derrubava mensagens legítimas como "Você é a próxima da fila!".
    /\A\s*Você é (a Bea|uma? (recepcionista|assistente|atendente))/i
  ].freeze

  Result = Struct.new(:text, :model, :input_tokens, :output_tokens, keyword_init: true)

  # Fase 5: recebe a `conversation` pra ler o histórico recente antes de
  # gerar (o "get_conversation"). O `patient_memory` é resolvido aqui
  # mesmo (a partir de contact+account) pra não inflar a assinatura.
  def initialize(rule:, contact:, step: nil, agenda_event: nil, conversation: nil)
    @rule = rule
    @step = step
    @contact = contact
    @agenda_event = agenda_event
    @conversation = conversation
  end

  def call
    # BE-26 (auditoria 2026-05-18): gate de cost cap. Sem isso, follow-ups
    # automáticos continuariam disparando mesmo após a conta estourar o
    # teto mensal — ChatService.respond bloqueia turnos síncronos mas
    # MessageGenerator rodava livre.
    return nil if cost_cap_blocked?

    # Garante que RubyLLM tem as keys configuradas. Em workers Sidekiq
    # o initializer do app pode não ter rodado (ou foi resetado). Chamar
    # `initialize!` aqui é idempotente — só configura uma vez por
    # processo, custo zero nas chamadas subsequentes.
    ::Llm::Config.initialize! if defined?(::Llm::Config)

    # `assume_model_exists`: espelha o ChatService — sem isso a gem valida
    # o nome contra o registro interno dela e modelos novos (gemini-3.5-*)
    # estouram ModelNotFoundError mesmo sendo válidos na API.
    chat = RubyLLM.chat(model: pick_model, provider: provider_name, assume_model_exists: true)
    chat.with_instructions(system_prompt)

    response = chat.ask(user_brief)
    text = response.content.to_s.strip

    return nil if text.empty?

    # SEC-25: valida que output parece mensagem natural pra paciente.
    # Tudo que cair fora dos padrões → descarta e marca execution como
    # failed (caller trata `nil`). Telemetria via warn pro caso de
    # ajustar prompt depois.
    return nil unless output_looks_like_message?(text)

    Result.new(
      text: text,
      model: pick_model,
      input_tokens: response.input_tokens.to_i,
      output_tokens: response.output_tokens.to_i
    )
  rescue StandardError => e
    Rails.logger.warn("[AiAgent::FollowUps::MessageGenerator] rule=#{@rule.id} contact=#{@contact&.id} #{e.class}: #{e.message[0, 200]}")
    nil
  end

  private

  # Monta o system prompt em camadas de tom, da mais geral pra mais específica:
  #   1. BASE_PROMPT      — regras de segurança + tom neutro padrão
  #   2. tom da CLÍNICA   — perfil de estilo da conta (projeto tom de voz), se
  #                         ativo; prioritário em COMO falar sobre o neutro
  #   3. tom da CAMPANHA  — persona_override da regra (Fase 5), prioritário
  #                         sobre tudo acima
  # As regras de segurança do BASE_PROMPT seguem soberanas em qualquer caso.
  def system_prompt
    parts = [BASE_PROMPT]

    style = AiAgent::StyleProfile::PromptSection.for_account(rule_account)
    # O BASE_PROMPT proíbe emoji/gíria por NOME (ex.: "nunca 👋🙂😊"). O perfil
    # da clínica pode legitimamente pedir exatamente esses — então um preâmbulo
    # de desempate explícito: a allow-list da clínica vence a deny-list nominal
    # acima; só as regras de SEGURANÇA e o teto de 3 frases seguem soberanos.
    if style.present?
      parts << 'O perfil de tom da clínica abaixo SUBSTITUI as restrições de ' \
               'estilo do tom padrão acima (emoji, saudação, gírias): a lista ' \
               'de emojis da clínica vale mesmo que algum apareça como proibido ' \
               'acima. As regras de segurança e o limite de no máximo 3 frases ' \
               "permanecem.\n\n#{style}"
    end

    persona = @rule.persona_override.to_s.strip
    parts << "TOM DESTE FOLLOW-UP (prioritário sobre o tom acima):\n#{persona}" if persona.present?

    parts.join("\n\n")
  end

  # Conta dona da regra — fonte de verdade do tenant (rule sempre vinculada).
  def rule_account
    @rule_account ||= ::Account.find_by(id: @rule.account_id)
  end

  # Cenário efetivo: o do passo da cadência quando houver, senão o da
  # própria regra (passo 1 / regras single-shot legadas).
  def effective_brief
    @step&.context_brief.presence || @rule.context_brief
  end

  def user_brief
    [
      "Cenário do follow-up: #{effective_brief}",
      '',
      "Nome do paciente: #{@contact.name.to_s.strip.presence || '(não identificado)'}",
      *appointment_lines,
      *preferences_lines,
      *history_lines,
      *knowledge_lines,
      '',
      'Escreva agora a mensagem que a Bea vai enviar pelo WhatsApp. Apenas a mensagem, sem explicação, sem prefixo.'
    ].join("\n")
  end

  # RAG no follow-up: busca na base de conhecimento da clínica trechos que
  # respondam à objeção/assunto do paciente (ex.: "não tenho dinheiro" →
  # parcelamento). Sem isto o follow-up vira um "ficou alguma dúvida?"
  # genérico. Best-effort: erro de embedding/credencial → segue sem RAG.
  def knowledge_lines
    query = last_patient_message.presence || effective_brief.to_s
    return [] if query.blank?

    hits = AiAgent::Rag::Retriever.new(rule_account, parent_limit: MAX_KNOWLEDGE).call(query)
    excerpts = Array(hits).first(MAX_KNOWLEDGE).filter_map { |h| h.parent_chunk.content.to_s.strip.presence }
    return [] if excerpts.empty?

    ['', 'Informações da clínica (base de conhecimento — use pra responder a dúvida/objeção; não invente além disto):',
     *excerpts.map { |e| "- #{e}" }]
  rescue StandardError => e
    Rails.logger.warn("[AiAgent::FollowUps::MessageGenerator] RAG falhou: #{e.message}")
    []
  end

  # Última mensagem do PACIENTE (incoming) — a objeção/assunto que o
  # follow-up deve endereçar. Usada como query do RAG.
  def last_patient_message
    return @last_patient_message if defined?(@last_patient_message)

    @last_patient_message = @conversation&.messages
                                         &.where(message_type: :incoming, private: false)
                                         &.reorder('messages.created_at DESC, messages.id DESC')
                                         &.limit(1)&.pick(:content).to_s.strip
  end

  def appointment_lines
    return [] if @agenda_event.nil?

    at = @agenda_event.starts_at.in_time_zone('America/Sao_Paulo')
    lines = ["Consulta: #{weekday_pt_br(at.strftime('%A'))}, #{at.strftime('%d/%m %H:%M')}"]
    lines << "Profissional: #{@agenda_event.user.name}" if @agenda_event.user
    lines << "Status atual: #{@agenda_event.status}"
    lines
  end

  def preferences_lines
    prefs = patient_memory&.preferences || {}
    return [] if prefs.blank?

    ["Preferências conhecidas: #{prefs.slice('preferred_time_of_day', 'preferred_professional').to_json}"]
  end

  def history_lines
    history = conversation_history
    return [] if history.empty?

    ['', 'Histórico recente da conversa (mais antigo → mais novo):', *history]
  end

  # Resolve a memória do paciente a partir de contact+account (a regra é
  # sempre a fonte de conta). Memoizado — usado só no user_brief.
  def patient_memory
    return @patient_memory if defined?(@patient_memory)

    @patient_memory = @contact && AiAgent::PatientMemory.find_by(account_id: @rule.account_id, contact_id: @contact.id)
  end

  # Últimas N mensagens (não-privadas) da conversa-alvo, em ordem
  # cronológica, como "Paciente: ..." / "Bea: ...". Vazio se não houver
  # conversa ou mensagens — aí a Bea escreve sem histórico.
  def conversation_history
    return [] if @conversation.nil?

    @conversation.messages
                 .where(message_type: %i[incoming outgoing], private: false)
                 .reorder('messages.created_at DESC, messages.id DESC')
                 .limit(HISTORY_LIMIT)
                 .to_a.reverse
                 .filter_map { |m| format_history_line(m) }
  end

  def format_history_line(message)
    body = message.content.to_s.strip
    return nil if body.blank?

    # Outgoing pode ser da Bea OU de um humano da clínica — rotula
    # genericamente "Clínica" pra não atribuir falas humanas à Bea.
    "#{message.incoming? ? 'Paciente' : 'Clínica'}: #{body}"
  end

  def weekday_pt_br(en)
    {
      'Monday' => 'segunda-feira',
      'Tuesday' => 'terça-feira',
      'Wednesday' => 'quarta-feira',
      'Thursday' => 'quinta-feira',
      'Friday' => 'sexta-feira',
      'Saturday' => 'sábado',
      'Sunday' => 'domingo'
    }[en] || en.downcase
  end

  def provider_name
    InstallationConfig.find_by(name: 'CAPTAIN_LLM_PROVIDER')&.value.presence || 'openai'
  end

  def pick_model
    case provider_name
    when 'gemini' then InstallationConfig.find_by(name: 'CAPTAIN_GEMINI_MODEL')&.value.presence || 'gemini-3-flash-preview'
    else InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_MODEL')&.value.presence || 'gpt-4.1-mini'
    end
  end

  # SEC-25: detecta output suspeito (estrutura JSON/código, eco do system
  # prompt, ou tamanho fora do esperado). Retorna false → MessageGenerator
  # descarta a tentativa em vez de enviar ao paciente.
  def output_looks_like_message?(text)
    if text.length > MAX_OUTPUT_CHARS
      Rails.logger.warn(
        "[AiAgent::FollowUps::MessageGenerator] rule=#{@rule.id} output too long " \
        "(#{text.length} > #{MAX_OUTPUT_CHARS}) — discarding"
      )
      return false
    end

    if STRUCTURED_OUTPUT_PATTERNS.any? { |p| p.match?(text) }
      Rails.logger.warn(
        "[AiAgent::FollowUps::MessageGenerator] rule=#{@rule.id} output looks structured " \
        "(JSON/code/eco) — discarding. Sample: #{text[0, 120].inspect}"
      )
      return false
    end

    true
  end

  # BE-26: bloqueia geração quando conta excedeu cap mensal. Caller
  # (SendFollowUpJob) trata nil como "marca execution como failed" sem
  # postar nada ao paciente — preserva integridade do limite.
  # `@rule.account_id` é o source of truth de conta (rule sempre vinculada);
  # contact pode ser nil em cenários edge.
  def cost_cap_blocked?
    account = rule_account
    return false if account.nil?

    over = AiAgent::ConfigResolver.new(account).over_monthly_cost_cap?
    Rails.logger.warn("[AiAgent::FollowUps::MessageGenerator] rule=#{@rule.id} skipped: monthly cost cap reached") if over
    over
  rescue StandardError => e
    Rails.logger.warn("[AiAgent::FollowUps::MessageGenerator] cost cap check failed: #{e.message}")
    false
  end
end
