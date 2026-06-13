# Last-mile sanity check on the LLM output before it goes to the patient.
# Cheap regex/heuristic checks — no LLM call. Catches the most common
# ways Bea can hurt the clinic:
#
#   - giving a medical diagnosis ("você tem X", "isso é Y")
#   - prescribing or dosing ("tome X mg de Y")
#   - guaranteeing outcomes ("vai resolver 100%", "garanto que")
#   - quoting prices that weren't in the knowledge base
#
# When a violation is found, the reply is replaced by a safe template
# and the conversation is escalated for a human review.
class AiAgent::Guardrail::Validator
  Result = Struct.new(:safe, :sanitized_message, :violations,
                      keyword_init: true) do
    def safe? = safe
  end

  # Termos clínicos que, quando acompanhados de afirmação categórica,
  # configuram diagnóstico. Mantemos a lista centralizada pra evitar
  # divergência entre patterns.
  MEDICAL_CONDITIONS = %w[
    c[aá]rie gengivite periodontite abscesso infec[cç][aã]o
    c[aâ]ncer tumor herpes candid[ií]ase alergia
    alergia\salimentar bruxismo p[uú]lpite sinusite
    pulpite g[eé]ngiva\sinflamada otite
  ].join('|').freeze

  DIAGNOSIS_PATTERNS = [
    # Afirmação direta: "você tem X / está com Y / sofre de Z / apresenta W"
    /\bvoc[eê] (?:tem|est[aá] com|sofre de|apresenta)\b.*\b(?:#{MEDICAL_CONDITIONS})/i,
    # Inferência ("isso é/parece X / é sinal de X") — exige termo clínico
    # depois pra não bloquear descrição neutra ("isso parece um escurecimento")
    /\bisso (?:[eé] (?:um|uma|sinal de)|parece (?:um|uma))\b.*\b(?:#{MEDICAL_CONDITIONS})/i,
    # Hedging suave: "pode ser / pode estar com X" + termo clínico
    /\b(?:pode ser|pode estar com)\b.*\b(?:#{MEDICAL_CONDITIONS})/i,
    # Hedging formal: "indicaria / indica / sugere / sugeriria X"
    /\b(?:indica(?:ria)?|sugere|sugeriria)\b.*\b(?:#{MEDICAL_CONDITIONS})/i,
    # Hipotético: "seria / seria uma X"
    /\bseria (?:um|uma)?\b.*\b(?:#{MEDICAL_CONDITIONS})/i,
    # "apresenta sintomas de X"
    /\bapresenta sintomas? (?:de|d['\s])\b.*\b(?:#{MEDICAL_CONDITIONS})/i,
    # "trata-se de (uma) X"
    /\btrata-se de (?:um|uma)?\b.*\b(?:#{MEDICAL_CONDITIONS})/i,
    # "tem cara de / tem aspecto de X" (coloquial)
    /\btem (?:cara|aspecto) de (?:um|uma)?\b.*\b(?:#{MEDICAL_CONDITIONS})/i
  ].freeze

  PRESCRIPTION_PATTERNS = [
    # Dose explícita: "tome 500 mg"
    /\btome (?:um |uma )?\d+ ?(?:mg|ml|comprimid|c[aá]psul)/i,
    # Nome de fármaco + dose
    /\b(?:ibuprofeno|paracetamol|amoxicilina|dipirona|nimesulida|amox|cefalexina|azitromicina|prednisona)\b.*\b(?:mg|ml|comprimid)/i,
    # Verbos de prescrição
    /\b(?:prescrev|recomendo (?:tomar|usar) o medicamento)/i,
    # Comece a tomar / use o remédio
    /\b(?:comece a tomar|comece a usar)\b.*\b(?:rem[eé]dio|medicamento|comprimid|antibi[oó]tico)/i,
    # "use X mg" / "use X ml"
    /\buse\b.*\b\d+ ?(?:mg|ml)/i
  ].freeze

  GUARANTEE_PATTERNS = [
    /\b(?:garant(?:o|imos|ido)|com certeza absoluta|100%\s*(?:de )?(?:efic|cura|sucesso|resolu)|sem (?:nenhum |qualquer )?risco)\b/i,
    /\bvai (?:com certeza |certamente )?(?:resolver|curar|sumir|sarar)\b/i,
    # Determinismo de resultado
    /\b(?:fica|ficar[aá]) (?:totalmente |completamente )?curad/i,
    # "resolve sem problema / sem dor / sem efeito colateral"
    /\bresolve sem (?:problema|dor|efeito)/i
  ].freeze

  SAFE_FALLBACK = <<~PT.strip
    Para essa dúvida específica, vou pedir para um da nossa equipe falar
    com você diretamente — assim você recebe a orientação correta. Só um
    instante.
  PT

  def initialize(message, context: nil, first_turn: true)
    @message = message.to_s
    @context = context
    @first_turn = first_turn
  end

  # Frases banidas pelo dono (soam frias/robóticas). Troca DETERMINÍSTICA —
  # não depende do LLM obedecer o prompt. Cosmético: reescreve a saída antes
  # de ir pro paciente. "transferir pro setor responsável" é a forma que o
  # dono pediu no lugar de "transferir pra um atendente humano".
  BANNED_PHRASING = [
    [/\b(?:para|pra)\s+(?:um |uma |o |a )?atendentes? humanos?\b/i, 'pro setor responsável'],
    [/\b(?:para|pra)\s+(?:o |ao )?atendimento humano\b/i, 'pro setor responsável'],
    [/\batendentes? humanos?\b/i, 'setor responsável'],
    [/\batendimento humano\b/i, 'setor responsável']
  ].freeze

  def call
    violations = []

    violations << 'medical_diagnosis' if matches_any?(DIAGNOSIS_PATTERNS)
    violations << 'prescription'      if matches_any?(PRESCRIPTION_PATTERNS)
    violations << 'guarantee'         if matches_any?(GUARANTEE_PATTERNS)

    return Result.new(safe: false, sanitized_message: SAFE_FALLBACK, violations: violations) unless violations.empty?

    # Mesmo seguro, limpa as frases banidas antes de mandar ao paciente.
    Result.new(safe: true, sanitized_message: sanitize_phrasing(@message), violations: [])
  end

  private

  def sanitize_phrasing(text)
    cleaned = BANNED_PHRASING.reduce(text.to_s) { |acc, (re, rep)| acc.gsub(re, rep) }
    cleaned = strip_regreeting(cleaned) unless @first_turn
    strip_dashes(cleaned)
  end

  # Recumprimentar no MEIO da conversa ("Olá, Leandro!" no 5º turno) é
  # proibido pelo prompt, mas o LLM ignora de vez em quando — corte
  # DETERMINÍSTICO: fora do 1º turno, remove a saudação inicial da resposta.
  # Se a mensagem for SÓ a saudação, mantém (não mandar bolha vazia).
  REGREETING = /\A\s*(?:ol[aá]|oi|opa|bom dia|boa tarde|boa noite|boa madrugada)(?:\s*,?\s*[\p{Lu}][\p{L}]*)?\s*[!,.]*\s*/iu

  def strip_regreeting(text)
    remainder = text.sub(REGREETING, '')
    return text if remainder.strip.empty?

    remainder[0] = remainder[0].upcase if remainder[0]
    remainder
  end

  # O dono não quer travessão (—) nem meia-risca (–) em mensagem nenhuma.
  # Troca por vírgula (separando a oração) e normaliza a pontuação, sem
  # mexer em quebras de linha (preserva o resumo de agendamento multilinha).
  def strip_dashes(text)
    text.gsub(/[ \t]*[—–][ \t]*/, ', ')
        .gsub(/([.!?;:])[ \t]*,[ \t]+/, '\1 ')
        .gsub(/(\A|\n)[ \t]*,[ \t]*/, '\1')
        .gsub(/,[ \t]*,/, ',')
  end

  def matches_any?(patterns)
    patterns.any? { |re| @message.match?(re) }
  end
end
