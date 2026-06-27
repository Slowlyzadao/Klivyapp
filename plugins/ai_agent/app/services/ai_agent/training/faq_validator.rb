# Estágio 5.5 — Validação semântica (o "juiz"). Última barreira antes das FAQs
# virarem sugestão: uma segunda chamada LLM julga CADA FAQ extraída — é
# conhecimento PERMANENTE, INSTITUCIONAL e seguro pra Bea repetir a qualquer
# paciente? Pega o que regex nunca pega (pontualidade sem palavra-chave,
# conselho clínico individual, inversão de papéis, promoção com prazo) e fecha
# o furo da "lavagem": o extrator reescreve a FAQ sem as marcas de data, mas a
# FONTE (trecho literal da conversa) vai junto pro juiz, que vê a origem real.
#
# Vereditos: manter | reescrever (fato válido, texto contaminado — ex.: nome
# de paciente; o juiz devolve a versão limpa PRESERVANDO o tom da clínica —
# emoji/gíria/jeitão) | rejeitar (motivo logado).
# Fail-closed: FAQ sem veredito é rejeitada. Juiz indisponível → UNAVAILABLE
# (o job falha visível e o Sidekiq reprocessa — nunca publica sem validar).
class AiAgent::Training::FaqValidator
  include AiAgent::Training::LlmResilience

  # JSON de veredito ilegível — retryable: re-pedir costuma resolver.
  class MalformedVerdict < StandardError; end

  def self.call(faqs:, model: nil)
    new(faqs, model).call
  end

  def initialize(faqs, model)
    @faqs = Array(faqs)
    @model = model.presence || pick_model
  end

  # Retorna o array de FAQs aprovadas (com reescritas aplicadas) ou UNAVAILABLE
  # quando nem o primário nem o fallback conseguiram julgar.
  def call
    return [] if @faqs.empty?

    result = validate_with(@model)
    return result unless result == UNAVAILABLE

    fallback = ENV['AI_AGENT_FAQ_FALLBACK_MODEL'].presence || 'gemini-flash-lite-latest'
    return UNAVAILABLE if fallback == @model

    Rails.logger.warn("[AiAgent::Training::FaqValidator] '#{@model}' indisponível; fallback → '#{fallback}'")
    validate_with(fallback)
  end

  private

  # MalformedVerdict também é transitório (re-pedir resolve), além dos erros
  # de rede/limite do módulo.
  def retryable?(error)
    error.is_a?(MalformedVerdict) || super
  end

  def validate_with(model)
    with_model_retries(model) { judge_once(model) }
  end

  def judge_once(model)
    chat = build_chat(model)
    chat.with_instructions(system_prompt)
    response = chat.ask(render_input)
    apply(parse_verdicts(response.content))
  end

  def system_prompt
    <<~PROMPT
      Você é o AUDITOR FINAL da base de conhecimento de uma assistente virtual
      (Bea) de uma clínica. Cada item abaixo foi extraído de uma conversa real
      de WhatsApp e tem PERGUNTA, RESPOSTA e FONTE (o trecho LITERAL da conversa
      que originou o item). A Bea vai repetir a RESPOSTA pra QUALQUER paciente,
      a QUALQUER momento. Seu trabalho NÃO é ser o mais rígido possível — é
      preservar o conhecimento INSTITUCIONAL da clínica e barrar só o que é
      pontual, clínico-individual, pessoal ou inútil.

      ⭐ CONHECIMENTO INSTITUCIONAL CORE — SEMPRE manter (ou reescrever se o
      texto estiver poluído; NUNCA rejeitar por isso ser "genérico demais" ou
      por estar mal redigido):
      - Como agendar / como funciona a primeira consulta / avaliação.
      - QUAIS dados ou documentos o paciente precisa levar/informar (RG, CPF,
         carteirinha). Pedir dados ≠ conter dados de alguém — isso É institucional.
      - Horário de funcionamento e dias de atendimento, mesmo se vagos
         ("segunda a sexta, horários variados" → MANTÉM).
      - Endereço, como chegar, estacionamento.
      - Procedimentos/serviços oferecidos e como funcionam (materiais, etapas).
      - Política de cancelamento/falta, formas de pagamento e parcelamento PADRÃO,
         convênios aceitos em geral, desconto permanente ("10% no PIX"),
         preços de TABELA fixos.

      REJEITE o item se ele cair em QUALQUER uma destas categorias (mire AQUI):
      1. PONTUAL: oferta/combinação de horário ou data pra uma pessoa,
         remarcação, encaixe, confirmação de consulta, lista de espera.
      2. ESTADO MOMENTÂNEO: agenda lotada/fechada, "essa semana", sistema fora,
         falta de insumo/estoque — o que muda de uma semana pra outra. (NÃO
         confunda com horário de funcionamento fixo, que é institucional.)
      3. PROMOÇÃO COM PRAZO ou escassez: "até sexta", "só esse mês", campanha
         sazonal (Black Friday, Outubro Rosa), "pros 10 primeiros".
      4. NEGOCIAÇÃO INDIVIDUAL: preço/desconto concedido como exceção a uma
         pessoa ("pra você", "falei com o doutor", "abro exceção"). Um preço de
         tabela normal NÃO é negociação — é institucional, mantém.
      5. CLÍNICO CASO-ESPECÍFICO: medicação/dose, diagnóstico, conduta dita pra
         o caso de UM paciente ("seu dente 36", "sua filha"). Saúde é caso a
         caso — só passa se for política geral explícita da clínica.
      6. PROMESSA DE RESULTADO: "garanto", "fica perfeito", "sem dor nenhuma".
      7. CONTRATO INDIVIDUAL: cobertura/regra do convênio DE UM paciente.
      8. DADOS PESSOAIS REAIS: o texto CONTÉM o dado de alguém identificável
         (ex.: "a paciente Maria Silva", um CPF/telefone real, o caso de um
         terceiro). ATENÇÃO: EXPLICAR quais documentos/dados o paciente deve
         fornecer NÃO é dado pessoal — é institucional e DEVE ser mantido.
         Nome de PROFISSIONAL da clínica ("Dr. Rafael atende às terças") é ok.
      9. SEM CONTEÚDO REAL: resposta adiada ("vou verificar e te retorno"),
         que é outra pergunta, saudação. "Depende do caso, na avaliação a gente
         define" PODE ser mantido se for a política real da clínica.
      10. INVERSÃO DE PAPEL: a informação veio do PACIENTE, não da clínica
          (cheque a fonte).
      11. TRANSCRIÇÃO QUEBRADA: texto truncado/sem sentido (origem em áudio).
      12. REFERÊNCIA ÓRFÃ: "como te falei", "o vídeo que mandei", "naquele
          valor que combinamos" — não se sustenta fora da conversa original.

      REESCREVA (em vez de rejeitar) quando o FATO for institucional válido mas
      o texto tiver um detalhe removível (NOME PRÓPRIO de paciente ou uma DATA
      específica). Ao reescrever, TIRE só esse detalhe e PRESERVE O JEITO DA
      CLÍNICA FALAR. ATENÇÃO: emojis, termos de carinho ("amor", "querida", "meu
      bem", "viu", "tá") e o tom acolhedor/informal são ESTILO da clínica, NÃO
      são dado pessoal — MANTENHA. Só nome próprio e data saem. A resposta deve
      continuar SOANDO como a clínica, não virar texto corporativo neutro.
      Exemplo: "Oi Nancy! 😊 Atendemos sábado das 8 às 12, pode vir tranquila
      amor!" → "Oii! 😊 Atendemos sábado das 8 às 12, pode vir tranquila amor!"
      (tirou só o nome; manteve o emoji, o "amor" e o jeitão). NÃO invente nada
      fora da fonte nem adicione emoji que ela não usou. Prefira REESCREVER a
      rejeitar quando for core.

      REGRA DE DECISÃO:
      - É conhecimento institucional core? → manter ou reescrever. Nunca rejeitar.
      - É clínico-individual, pessoal, pontual, promo com prazo ou vazio? →
        rejeitar. Na dúvida ENTRE ESSES, rejeite (melhor a Bea não saber do que
        dar conselho médico ou furar preço).

      Responda APENAS um array JSON (nada antes nem depois), com UM objeto por
      item, na ordem: {"i": <índice>, "v": "manter"|"reescrever"|"rejeitar",
      "motivo": "<curto, só no rejeitar>", "pergunta": "<só no reescrever>",
      "resposta": "<só no reescrever>"}
    PROMPT
  end

  def render_input
    @faqs.each_with_index.map do |faq, index|
      <<~ITEM
        ##{index}
        PERGUNTA: #{faq['pergunta_paciente']}
        RESPOSTA: #{faq['resposta_clinica']}
        FONTE: #{faq['fonte'].presence || '(sem fonte registrada)'}
      ITEM
    end.join("\n")
  end

  # Veredito por índice. Array ilegível/ausente → MalformedVerdict (retry).
  def parse_verdicts(content)
    text = content.to_s.strip.sub(/\A```(?:json)?\s*/i, '').sub(/```\s*\z/i, '').strip
    start = text.index('[')
    finish = text.rindex(']')
    raise MalformedVerdict, 'resposta sem array JSON' if start.nil? || finish.nil? || finish < start

    parsed = JSON.parse(text[start..finish])
    raise MalformedVerdict, 'array de vereditos inválido' unless parsed.is_a?(Array)

    parsed.select { |verdict| verdict.is_a?(Hash) }.index_by { |verdict| verdict['i'].to_i }
  rescue JSON::ParserError => e
    raise MalformedVerdict, "JSON ilegível: #{e.message[0, 120]}"
  end

  # Fail-closed: sem veredito = rejeitada. Reescrita vazia também rejeita
  # (o juiz não pode "salvar" um item sem entregar o texto limpo).
  def apply(verdicts)
    @faqs.each_with_index.filter_map do |faq, index|
      verdict = verdicts[index]
      case verdict&.dig('v')
      when 'manter' then faq
      when 'reescrever' then rewrite(faq, verdict, index)
      else reject(faq, index, verdict&.dig('motivo') || 'sem veredito do juiz')
      end
    end
  end

  def rewrite(faq, verdict, index)
    question = verdict['pergunta'].to_s.strip
    answer = verdict['resposta'].to_s.strip
    return reject(faq, index, 'reescrita vazia') if question.empty? || answer.empty?

    faq.merge('pergunta_paciente' => question[0, 500], 'resposta_clinica' => answer[0, 2000])
  end

  def reject(faq, index, reason)
    Rails.logger.info(
      "[AiAgent::Training::FaqValidator] rejeitada ##{index} (#{reason}): #{faq['pergunta_paciente'].to_s[0, 80]}"
    )
    nil
  end

  # Mesmo modelo (e env) da extração — barato, 1 chamada por conversa.
  def pick_model
    ENV['AI_AGENT_FAQ_MODEL'].presence || 'gpt-4o-mini'
  end
end
