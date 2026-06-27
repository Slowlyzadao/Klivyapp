# Projeto "Tom de voz da Bea" — Fase 2 (geração).
#
# Destila o ESTILO de comunicação da clínica a partir das mensagens REAIS dela
# (role CLINICA) nas conversas concluídas do Treinamento. Produz o hash de
# rascunho consumido pelo AiAgent::StyleProfile::PromptSection (Fase 1).
#
# Filosofia (igual FaqExtractor: guard determinístico + LLM):
#   - EMOJIS: extraídos por regex e contados — o set REAL dela, sem alucinação.
#   - EXEMPLOS few-shot: o LLM só ESCOLHE os índices dos pares mais
#     representativos; o texto vem VERBATIM da lista (anti-alucinação, espelha
#     o verify_sources). O texto já vem PII-mascarado do ChatParser.
#   - TRAÇOS qualitativos (summary/greeting/closing/expressions): LLM.
#
# Reusa a resiliência LLM compartilhada do Treinamento (retry/backoff,
# sentinela UNAVAILABLE, credenciais Gemini, temperatura 0).
class AiAgent::StyleProfile::Distiller
  include AiAgent::Training::LlmResilience

  # Input deterministicamente insuficiente — a clínica não tem texto suficiente
  # nas conversas concluídas. Job marca o rascunho como failed, sem retry.
  class InsufficientData < StandardError; end

  ROLE_CLINIC = AiAgent::Training::ChatParser::ROLE_CLINIC
  ROLE_PATIENT = AiAgent::Training::ChatParser::ROLE_PATIENT
  TYPE_TEXT = AiAgent::Training::ChatParser::TYPE_TEXT

  MIN_MESSAGES = 5            # abaixo disso não dá pra inferir um tom
  MAX_CONVERSATIONS = 50      # teto de conversas lidas
  MAX_CLINIC_MSGS = 200       # amostra de mensagens enviada ao LLM
  MAX_PAIRS = 50              # pares candidatos numerados pro LLM escolher
  MAX_EXAMPLES_OUT = 10       # exemplos no rascunho final (= cap do renderer)
  MAX_EMOJIS_OUT = 10
  MSG_CLIP = 200              # corte por mensagem ao montar o payload

  # Faixas Unicode dos emojis/símbolos mais comuns em WhatsApp BR (pictográficos,
  # dingbats, setas, símbolos diversos). Variation selectors são ignorados.
  EMOJI_RE = /[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}\u{2B00}-\u{2BFF}\u{2190}-\u{21FF}]/

  # Placeholder de mídia omitida no export ("áudio ocultado", "imagem omitida",
  # "audio omitted") — não é estilo da clínica.
  MEDIA_OMITTED = /\A\s*
    (áudio|audio|imagem|image|v[íi]deo|video|figurinha|sticker|gif|
     documento|document|foto|contato|contact|localiza[çc][ãa]o|location)
    \s+(ocultad|omitid|omitt|hidden|indispon|n[ãa]o\s+dispon)/xi

  # Artefatos do export do WhatsApp que escapam do SYSTEM_NOISE do ChatParser
  # e NÃO são estilo da clínica (aviso de conta Business da Meta + mídia omitida).
  # Filtrados aqui pra não virarem greeting/exemplo nem sujar o tom.
  STYLE_NOISE = [/servi[çc]o seguro da meta/i, /gerenciar esta conversa/i, MEDIA_OMITTED].freeze

  def self.call(account:)
    new(account).call
  end

  def initialize(account)
    @account = account
    # gpt-4o-mini por padrão (mesma env do FaqExtractor); roda 1x por geração.
    @model = ENV['AI_AGENT_FAQ_MODEL'].presence || 'gpt-4o-mini'
  end

  # Retorna o hash do rascunho, ou UNAVAILABLE quando o LLM não respondeu
  # (primário + fallback esgotados). Levanta InsufficientData quando não há
  # mensagens suficientes da clínica.
  def call
    messages = clinic_messages
    if messages.size < MIN_MESSAGES
      raise InsufficientData,
            'Não há mensagens suficientes da clínica nas conversas concluídas. ' \
            'Suba conversas no Treinamento e gere o tom de voz depois.'
    end

    pairs = sample(example_pairs, MAX_PAIRS)
    traits = distill_traits(sample(messages, MAX_CLINIC_MSGS), pairs)
    return UNAVAILABLE if traits == UNAVAILABLE

    traits = {} unless traits.is_a?(Hash)
    build_profile(messages, pairs, traits)
  end

  private

  def build_profile(messages, pairs, traits)
    @redactor = AiAgent::StyleProfile::NameRedactor.new(sender_names + Array(traits['names_to_redact']))
    {
      # TODOS os campos textuais passam pelo redactor (LGPD) — summary e
      # expressions são gerados pelo LLM e podem bordar um nome apesar do prompt.
      'summary' => clean_field(traits['summary'], 280),
      'greeting' => clean_field(traits['greeting'], 280),
      'closing' => clean_field(traits['closing'], 280),
      'emojis' => top_emojis(messages),
      'expressions' => clip_list(traits['expressions'], 18, 90).map { |expr| @redactor.redact(expr) },
      'examples' => build_examples(pairs, traits['example_indices']),
      'sample_count' => messages.size,
      'source_conversation_count' => conversations.size,
      'generated_at' => Time.current.iso8601
    }
  end

  # Corta e redige nome (LGPD) de um campo textual do perfil.
  def clean_field(value, limit)
    @redactor.redact(clip(value, limit))
  end

  # Conversas concluídas da conta, mais recentes primeiro. INCLUI arquivadas:
  # arquivar é "tirar da lista", não "não aprender com ela" — o estilo da
  # clínica nas msgs continua valioso pro tom (só conversa DELETADA some de vez).
  def conversations
    @conversations ||= @account.ai_agent_training_conversations
                               .where(status: :completed)
                               .order(created_at: :desc)
                               .limit(MAX_CONVERSATIONS)
                               .to_a
  end

  # Todas as falas TEXTO da clínica (já PII-mascaradas no parse), sem ruído de
  # export.
  def clinic_messages
    @clinic_messages ||= conversations.flat_map do |conv|
      Array(conv.parsed_messages).filter_map do |msg|
        next unless msg['role'] == ROLE_CLINIC && msg['type'] == TYPE_TEXT

        text = msg['text'].to_s.strip
        text.presence unless noise?(text)
      end
    end
  end

  def noise?(text)
    STYLE_NOISE.any? { |re| re.match?(text) }
  end

  # Pares pergunta(paciente)→resposta(clínica) adjacentes — candidatos a
  # exemplo few-shot. Texto verbatim (já PII-mascarado no parse).
  def example_pairs
    conversations.flat_map do |conv|
      texts = Array(conv.parsed_messages).select { |msg| msg['type'] == TYPE_TEXT }
      texts.each_cons(2).filter_map { |patient, clinic| pair_for(patient, clinic) }
    end
  end

  def pair_for(patient, clinic)
    return unless patient['role'] == ROLE_PATIENT && clinic['role'] == ROLE_CLINIC

    paciente = patient['text'].to_s.strip
    clinica = clinic['text'].to_s.strip
    return if paciente.empty? || clinica.empty?
    return if noise?(paciente) || noise?(clinica)

    { 'paciente' => paciente, 'clinica' => clinica }
  end

  # Top emojis REAIS por frequência — determinístico, sem LLM.
  def top_emojis(messages)
    counts = Hash.new(0)
    messages.each { |text| text.scan(EMOJI_RE) { |emoji| counts[emoji] += 1 } }
    counts.sort_by { |_emoji, count| -count }.first(MAX_EMOJIS_OUT).map(&:first)
  end

  # Só pares com índice válido (o LLM escolheu); texto VERBATIM da lista, com
  # nomes de paciente redigidos (LGPD).
  def build_examples(pairs, indices)
    Array(indices).filter_map { |i| pairs[i.to_i] if i.to_s.match?(/\A\d+\z/) }
                  .uniq
                  .first(MAX_EXAMPLES_OUT)
                  .map { |pair| { 'paciente' => @redactor.redact(pair['paciente']), 'clinica' => @redactor.redact(pair['clinica']) } }
  end

  # `sender` das falas PACIENTE — uma das fontes de nome a redigir (a outra são
  # os nomes que o LLM detecta no texto). Pode ser telefone (aí não vira nome).
  def sender_names
    conversations.flat_map { |conv| Array(conv.parsed_messages) }
                 .filter_map { |msg| msg['sender'].to_s if msg['role'] == ROLE_PATIENT }
  end

  # Chama o LLM com fallback de modelo. Sucesso = Hash (mesmo {} de parse vazio).
  # `[]` (erro DEFINITIVO: billing/auth/bug) e UNAVAILABLE (retries esgotados)
  # NÃO são Hash → tenta o fallback; se o fallback também não der Hash, devolve
  # UNAVAILABLE pro job falhar VISÍVEL — em vez de gravar um rascunho vazio como
  # 'ready' (um `[]` definitivo do primário não pode virar sucesso silencioso).
  def distill_traits(messages, pairs)
    result = run_llm(@model, messages, pairs)
    return result if result.is_a?(Hash)

    fallback = ENV['AI_AGENT_FAQ_FALLBACK_MODEL'].presence || 'gemini-flash-lite-latest'
    return UNAVAILABLE if fallback == @model

    Rails.logger.warn("[AiAgent::StyleProfile::Distiller] '#{@model}' indisponível; fallback → '#{fallback}'")
    fb = run_llm(fallback, messages, pairs)
    fb.is_a?(Hash) ? fb : UNAVAILABLE
  end

  def run_llm(model, messages, pairs)
    with_model_retries(model) do
      chat = build_chat(model)
      chat.with_instructions(system_prompt)
      response = chat.ask(user_payload(messages, pairs))
      parse(response.content)
    end
  end

  def system_prompt
    <<~PROMPT
      Você analisa como uma CLÍNICA escreve no WhatsApp para um assistente
      virtual imitar o JEITO dela falar (o tom, não o conteúdo). Recebe
      mensagens reais da clínica e pares pergunta(paciente)→resposta(clínica).

      Extraia o ESTILO de comunicação (nunca fatos, preços, horários, nomes ou datas):
      - summary: 2-4 frases DETALHADAS sobre o tom — formalidade (você/senhor,
        gírias), nível de calor/informalidade, ritmo e tamanho das frases, uso de
        emoji, e COMO ela conduz (cumprimenta, confirma, contorna objeção,
        tranquiliza, se despede).
      - greeting: como ela COSTUMA abrir/cumprimentar (no jeito dela).
      - closing: como ela COSTUMA encerrar/se despedir.
      - expressions: bordões/expressões e gírias característicos (curtos), o
        máximo que conseguir observar (até ~15), array de strings.
      - example_indices: os índices (8 a 12) dos PARES mais representativos e
        VARIADOS do tom — cubra SITUAÇÕES diferentes (dúvida, preço, agendamento,
        reclamação, pós-atendimento), não só saudações.
      - names_to_redact: TODOS os nomes próprios de pessoas (pacientes) que
        aparecerem nas mensagens/pares — pra remoção (LGPD). Liste cada primeiro
        nome/sobrenome que você vir. Array de strings (vazio se não houver).

      Regras:
      - Reflita só o que foi REALMENTE observado — não invente nem suavize.
      - NÃO inclua dados pessoais, valores, datas nem nomes próprios nos campos
        de estilo (summary/greeting/closing/expressions).
      - Responda APENAS um objeto JSON válido, sem markdown, sem texto fora:
      {"summary":"...","greeting":"...","closing":"...","expressions":["..."],"example_indices":[0,1,2],"names_to_redact":["..."]}
    PROMPT
  end

  def user_payload(messages, pairs)
    numbered = pairs.each_with_index.map do |pair, i|
      "[#{i}] Paciente: #{clip(pair['paciente'], MSG_CLIP)}\n    Clínica: #{clip(pair['clinica'], MSG_CLIP)}"
    end
    [
      'MENSAGENS DA CLÍNICA (como ela escreve):',
      *messages.map { |text| "- #{clip(text, MSG_CLIP)}" },
      '',
      'PARES candidatos (escolha os índices dos mais representativos do TOM):',
      *numbered
    ].join("\n")
  end

  def parse(content)
    text = content.to_s.strip.sub(/\A```(?:json)?\s*/i, '').sub(/```\s*\z/i, '').strip
    start = text.index('{')
    finish = text.rindex('}')
    return {} if start.nil? || finish.nil? || finish < start

    parsed = JSON.parse(text[start..finish])
    parsed.is_a?(Hash) ? parsed : {}
  rescue JSON::ParserError => e
    Rails.logger.warn("[AiAgent::StyleProfile::Distiller] parse falhou: #{e.message[0, 200]}")
    {}
  end

  # Amostra uniformemente espaçada (determinística) pra caber no teto sem
  # enviesar pra uma conversa só.
  def sample(arr, max)
    return arr if arr.size <= max

    stride = arr.size / max
    arr.each_with_index.select { |_item, i| (i % stride).zero? }.map(&:first).first(max)
  end

  def clip(value, limit)
    value.to_s.strip[0, limit].to_s
  end

  def clip_list(value, max_items, limit)
    Array(value).first(max_items).filter_map { |item| clip(item, limit).presence }
  end
end
