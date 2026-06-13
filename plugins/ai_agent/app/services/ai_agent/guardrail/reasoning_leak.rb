# Detecta quando o LLM VAZA o raciocínio interno na mensagem ao paciente
# (chain-of-thought exposto). Gemini 3.5-flash é modelo de "thinking" e, mesmo
# com thinkingBudget=0, às vezes escreve o plano/raciocínio COMO resposta:
#
#   "Como o Leandro escolheu o horário das 10:00 e não possui cadastro
#    (retornou found: false), preciso solicitar o Nome Completo e o CPF dele.
#    Uma pergunta por vez. Vou primeiro confirmar... para manter o limite de
#    3 frases..."
#
# Nada disso pode chegar ao paciente. Os padrões abaixo são de ALTA confiança
# (coisas que JAMAIS aparecem numa fala natural de recepcionista): nomes de
# tools, refs a variáveis (found:), citação das próprias regras ("regra VOCÊ",
# "limite de 3 frases"), e narração de plano em 3ª pessoa sobre o paciente.
module AiAgent::Guardrail::ReasoningLeak
  TOOL_NAMES = %w[
    find_patient_by_phone confirm_patient_identity clinic_info
    search_available_slots book_appointment cancel_appointment
    reschedule_appointment add_to_waiting_list create_patient_minimal
    update_patient_record search_knowledge transfer_to_human notify_staff
    list_appointments patient_lookup financial_status
  ].freeze

  PATTERNS = [
    # Nome de tool citado literalmente
    /\b(?:#{TOOL_NAMES.join('|')})\b/,
    # Ref a variável/retorno de tool ("found: false", "found:true")
    /\bfound\s*:/i,
    # Citação das próprias regras do sistema
    /\blimite de \d+ frases?\b/i,
    /\bregra\s+["“'']?voc[êe]\b/i,
    /\buma pergunta por vez\b/i,
    /\bpara (?:ser direto|manter o limite)\b/i,
    # Narração de plano ("vou primeiro confirmar/pedir...")
    /\bvou primeiro\b/i,
    # Narração em 3ª pessoa SOBRE o paciente ("Como o Fulano escolheu... não
    # possui cadastro"). [Cc] EXPLÍCITO: o chain-of-thought quase sempre ABRE
    # a frase com "Como..." maiúsculo — foi exatamente assim que um vazamento
    # real passou (2026-06-11). Não dá pra usar /i no padrão inteiro porque
    # \p{Lu} precisa continuar exigindo Nome próprio capitalizado (senão
    # "como a gente não tem horário..." viraria falso positivo).
    /\b[Cc]omo (?:o|a) \p{Lu}[\p{L}]+ (?:escolheu|selecionou|pediu|informou|confirmou|quer|deseja|n[ãa]o possui|n[ãa]o tem|n[ãa]o informou|j[áa] possui|j[áa] tem|est[áa] com)\b/u,
    # "preciso solicitar/confirmar ... dele/dela/ele mesmo" (fala sobre o paciente, não com ele)
    /\bpreciso (?:solicitar|confirmar|pedir|verificar)\b[^.!?]*\b(?:dele|dela|ele mesmo|ela mesma)\b/i,
    # Narração de processo/fluxo (vocabulário interno do prompt — uma
    # recepcionista de verdade nunca fala assim com o paciente)
    /\bpreciso (?:iniciar|seguir|aplicar|executar|continuar) o (?:processo|fluxo)\b/i,
    /\bfluxo (?:obrigat[óo]rio|de agendamento|de cadastro|de cancelamento)\b/i,
    /\bconforme (?:o fluxo|a regra|as regras|as instru[çc][õo]es|o prompt)\b/i,
    /\(\s*para quem\s*\+\s*queixa\s*\)/i,
    # Refs a estruturas internas do contexto/sistema injetadas pela gente
    /\bCONTEXTO ATUAL\b/,
    /\bIDs? internos?\b/i,
    /\bsystem prompt\b/i,
    # Jargão jurídico/institucional que recepcionista humana JAMAIS fala com
    # paciente (vazou na prática: "seus dados ficam protegidos pela LGPD").
    # Detectar dispara a reescrita — a frase volta coloquial.
    /\bLGPD\b/,
    /\bCFM\b/,
    /\bprote[çc][ãa]o de dados\b/i,
    /\bconselho federal de\b/i
  ].freeze

  def self.leaked?(text)
    s = text.to_s
    return false if s.strip.empty?

    PATTERNS.any? { |re| s.match?(re) }
  end

  # Remove as FRASES que contêm vazamento, preservando o resto (caso a
  # resposta misture raciocínio + uma pergunta legítima ao paciente).
  # Usado como rede de segurança quando a reescrita falha.
  def self.strip(text)
    sentences = text.to_s.split(/(?<=[.!?\n])\s+/)
    kept = sentences.reject { |sent| PATTERNS.any? { |re| sent.match?(re) } }
    kept.join(' ').strip
  end
end
