# Estágio 4 — Extração de FAQ (IA, temperatura 0). Para cada bloco, pede ao
# modelo um array JSON de pares pergunta→resposta com categoria e a FONTE (o
# trecho literal do bloco que gerou o item). Anti-alucinação: descarta todo
# item cuja `fonte` não apareça literalmente no bloco — item sem fonte
# verificável é invenção e vai fora.
#
# Segue o padrão de chamada/parse do AiAgent::Memory::Distiller. O modelo é
# configurável por env (`AI_AGENT_FAQ_MODEL`) pra usar uma variante barata.
class AiAgent::Training::FaqExtractor
  include AiAgent::Training::LlmResilience

  MAX_ITEMS = 20

  # Rede de segurança determinística: marcas de conteúdo EFÊMERO (vale só pra um
  # paciente naquele dia) que não podem virar conhecimento do RAG. O prompt já
  # pede pra ignorar, mas o LLM às vezes insiste — aqui é o corte garantido e
  # barato; a validação fina (semântica) é do FaqValidator, na etapa seguinte.
  # Calibrado pra NÃO pegar horário de funcionamento ("das 8h às 18h") nem
  # recorrência ("todo dia 5" — boleto, p.ex.).
  WRITTEN_DAYS = %w[
    primeiro um dois três tres quatro cinco seis sete oito nove dez onze doze
    treze quatorze catorze quinze dezesseis dezessete dezoito dezenove vinte trinta
  ].join('|').freeze
  EPHEMERAL_MARKERS = [
    /\b(amanh[ãa]|hoje|depois de amanh[ãa]|ontem)\b/i,
    /(?<!todo )(?<!todos os )\bdia\s+\d{1,2}\b/i,
    /(?<!todo )(?<!todos os )\bdia\s+(#{WRITTEN_DAYS})\b/i,
    /\bconsegui\b.*\b(pra|para)\s+(ti|voc[êe]|vc)\b/i,
    /\b(tenho|temos|tem)\b[^.?!]*\bhor[áa]rio\b[^.?!]*\b(pra|para)\s+(ti|voc[êe]|vc)\b/i,
    /\bantecip\w+\b[^.?!]*\b(pra|para)\b/i
  ].freeze

  def self.call(block_text:, model: nil)
    new(block_text, model).call
  end

  def initialize(block_text, model)
    @block_text = block_text.to_s
    @model = model.presence || pick_model
  end

  # Retorna o array de FAQs (possivelmente vazio) OU UNAVAILABLE quando nem o
  # primário nem o fallback responderam (ambos esgotaram retries).
  def call
    return [] if @block_text.strip.empty?

    result = extract_with_retries(@model)
    return result unless result == UNAVAILABLE

    # Primário indisponível (rate-limit / crédito) → cai pro modelo alternativo
    # pra não travar o treinamento. LOGADO pra não mascarar em silêncio.
    fallback = ENV['AI_AGENT_FAQ_FALLBACK_MODEL'].presence || 'gemini-flash-lite-latest'
    return UNAVAILABLE if fallback == @model

    Rails.logger.warn("[AiAgent::Training::FaqExtractor] '#{@model}' indisponível; fallback → '#{fallback}'")
    extract_with_retries(fallback)
  end

  private

  # Tenta o modelo com backoff exponencial em erros TRANSITÓRIOS (rate-limit de
  # RPM, 5xx, timeout). Retorna o array em sucesso, `[]` em erro definitivo
  # (parse/conteúdo — aceita e segue) ou UNAVAILABLE se esgotar os retries.
  def extract_with_retries(model)
    with_model_retries(model) { extract_once(model) }
  end

  # Uma chamada ao modelo. Levanta a exceção (pra o retry decidir) em vez de
  # engolir — `with_model_retries` é quem classifica e loga.
  def extract_once(model)
    chat = build_chat(model)
    chat.with_instructions(system_prompt)
    response = chat.ask(@block_text)

    reject_ephemeral(verify_sources(parse(response.content)))
  end

  # Derruba FAQs cujo conteúdo é pontual (data/horário específico, oferta de
  # agendamento) — verifica pergunta + resposta contra as marcas efêmeras.
  def reject_ephemeral(faqs)
    faqs.reject do |faq|
      text = "#{faq['pergunta_paciente']} #{faq['resposta_clinica']}"
      EPHEMERAL_MARKERS.any? { |marker| marker.match?(text) }
    end
  end

  def system_prompt
    <<~PROMPT
      Você lê um TRECHO de conversa real de WhatsApp de um negócio (clínica,
      consultório ou prestador de serviço) e extrai CONHECIMENTO PERMANENTE pra
      um assistente virtual responder QUALQUER cliente a QUALQUER momento.

      FORMATO DO TRECHO: cada linha começa com o papel de quem fala —
      "CLINICA:" é o negócio/atendente; "PACIENTE:" é o cliente. A resposta de
      um item DEVE vir de falas da CLINICA. O que o PACIENTE diz NUNCA é
      conhecimento do negócio (é relato/dúvida dele) — serve só como pergunta.

      O teste de ouro de cada item: "isso vale pra todo cliente, sempre?". Se a
      resposta só serve pra UMA pessoa, em UM momento, NÃO é conhecimento — é
      atendimento pontual e fica FORA.

      EXTRAIA apenas FATOS GERAIS e estáveis, como:
      - Preços de TABELA e formas de pagamento (valores fixos, parcelamento padrão,
        convênios aceitos, desconto permanente tipo "10% no PIX").
      - O que o negócio faz/oferece (procedimentos, serviços, especialidades).
      - Como funciona (regras de agendamento, cancelamento, documentos exigidos,
        preparo PADRÃO, política de avaliação, garantia formal).
      - Horário de FUNCIONAMENTO e dias fixos de atendimento dos profissionais.
      - Localização, endereço, como chegar, estacionamento.

      NÃO EXTRAIA (jogue fora — qualquer um destes):
      1. Oferta/combinação de horário ou data pra UM cliente: "consegui pra ti
         quarta às 14h", "amanhã tem vaga", "te encaixo sexta", remarcações,
         encaixes, lista de espera, confirmação de consulta de alguém.
      2. Estado momentâneo da agenda/operação: "essa semana tá lotado", "dezembro
         fechou", "estamos sem luz/sistema hoje", estoque/insumo do momento.
      3. Promoção ou campanha COM PRAZO ou escassez: "até sexta", "só esse mês",
         "Black Friday", "pros 10 primeiros". (Desconto SEM prazo é política → ok.)
      4. Preço/condição NEGOCIADA individualmente: "pra você eu faço por X",
         "falei com o doutor e consegui", "abrimos uma exceção", pacote montado
         pro caso de um paciente.
      5. ORIENTAÇÃO CLÍNICA de caso específico: medicação/dose ("toma ibuprofeno
         de 8 em 8h"), diagnóstico ("isso é canal"), conduta pós-operatória dita
         pra UM paciente, avaliação do caso de alguém. Saúde é caso a caso — só
         entra se for política GERAL e explícita da clínica.
      6. PROMESSA DE RESULTADO ("garanto que fica perfeito", "sem dor nenhuma").
      7. Convênio/cobertura de contrato INDIVIDUAL ("o seu plano cobre").
      8. Dados pessoais: nome de paciente, caso de terceiros, qualquer informação
         que identifique alguém.
      9. Resposta adiada/vazia ("vou verificar e te retorno", "depende", "a gente
         vê"), resposta que é outra pergunta, saudação, logística da conversa.
      10. Referência órfã: "como te falei", "igual o vídeo que mandei", "naquele
          valor que combinamos" — não faz sentido fora desta conversa.

      Responda APENAS um array JSON válido (nada antes nem depois). Cada item:
      {
        "pergunta_paciente": "<a dúvida, reescrita de forma GERAL, sem nomes/datas>",
        "resposta_clinica": "<a resposta GERAL e estável, sem data/horário específico>",
        "categoria": "<rótulo curto: preço, pagamento, procedimento, agendamento, cancelamento, horário, localização, documentos, escopo, suporte, outros>",
        "fonte": "<um trecho LITERAL e contínuo de uma fala da CLINICA que comprove a resposta — copie exatamente, sem alterar>"
      }

      Regras finais:
      - A `fonte` DEVE ser um recorte exato (copiar/colar) de fala da CLINICA. Sem
        trecho literal da clínica que comprove, NÃO inclua o item.
      - Na dúvida entre incluir e descartar: DESCARTE.
      - Sem markdown, sem ```json, sem texto fora do array. Se não houver nada
        GERAL e reutilizável, retorne [].
    PROMPT
  end

  def parse(content)
    text = content.to_s.strip
    text = text.sub(/\A```(?:json)?\s*/i, '').sub(/```\s*\z/i, '').strip
    start = text.index('[')
    finish = text.rindex(']')
    return [] if start.nil? || finish.nil? || finish < start

    parsed = JSON.parse(text[start..finish])
    return [] unless parsed.is_a?(Array)

    parsed.filter_map { |item| normalize(item) }.first(MAX_ITEMS)
  rescue JSON::ParserError => e
    Rails.logger.warn("[AiAgent::Training::FaqExtractor] parse falhou: #{e.message[0, 200]}")
    []
  end

  def normalize(item)
    return nil unless item.is_a?(Hash)

    question = item['pergunta_paciente'].to_s.strip
    answer = item['resposta_clinica'].to_s.strip
    return nil if question.empty? || answer.empty?

    {
      'pergunta_paciente' => question[0, 500],
      'resposta_clinica' => answer[0, 2000],
      'categoria' => (item['categoria'].to_s.strip.downcase[0, 40].presence || 'outros'),
      'fonte' => item['fonte'].to_s.strip
    }
  end

  # Anti-alucinação: a fonte precisa aparecer literalmente no bloco (tolerando
  # apenas diferença de espaçamento). Sem fonte verificável → descarta.
  def verify_sources(faqs)
    normalized_block = squish(@block_text)
    faqs.select do |faq|
      source = faq['fonte']
      source.present? && normalized_block.include?(squish(source))
    end
  end

  def squish(text)
    text.to_s.gsub(/\s+/, ' ').strip
  end

  # gpt-4o-mini por padrão: medido extraindo ~3x mais fatos que o Flash-Lite
  # (12 vs 4 numa conversa real) com custo irrisório (roda 1x por conversa).
  # NÃO herda o modelo caro da Bea (CAPTAIN_GEMINI_MODEL). Troca por env.
  def pick_model
    ENV['AI_AGENT_FAQ_MODEL'].presence || 'gpt-4o-mini'
  end
end
