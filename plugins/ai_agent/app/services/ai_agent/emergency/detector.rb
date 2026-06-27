require 'English'
# Classificador determinístico de emergências clínicas e ideação
# suicida via keyword/regex. Roda ANTES do LLM (referência: Mount
# Sinai 2026 / Nature Medicine — ChatGPT Health undertriage 52%
# de emergências reais; classificação NÃO pode ser delegada ao
# modelo). Lista alimentada pelo Apêndice C do plano de Bea.
#
# Filosofia: 0 falso negativo é prioridade absoluta. Falso
# positivo (mandar SAMU/CVV pra alguém que não precisava)
# custa atrito; falso negativo custa vida. Em dúvida, dispara.
class AiAgent::Emergency::Detector
  Match = Struct.new(:category, :keyword, keyword_init: true)

  # ─── Emergência clínica → SAMU 192 ────────────────────────────
  CLINICAL_PATTERNS = [
    # Vias aéreas / respiração
    /\bn[aã]o\s+(?:est[aá]\s+|consigo\s+)?respira(?:r|ndo)?\b/i,
    /\bparou\s+de\s+respirar\b/i,
    /\bsem\s+respira(?:r|[cç][aã]o)\b/i,
    /\bfalta\s+de\s+ar\s+(?:muito\s+)?(?:forte|grave|insuport[aá]vel)\b/i,
    /\b(?:engasgou|engasgando|engasgada|engasgado|engasgamento)\b/i,

    # Consciência
    /\b(?:desmaiou|desmaiei|desmaiar|desmaiando|inconsciente|sem\s+consci[eê]ncia)\b/i,
    /\bperdi\s+a\s+consci[eê]ncia\b/i,

    # Cardíaca / dor torácica
    /\bdor\s+(?:muito\s+)?(?:forte\s+)?no\s+peito\b/i,
    /\bdor\s+no\s+peito\s+(?:forte|insuport[aá]vel|aperto|esmagando|irradiando)\b/i,
    /\baperto\s+no\s+peito\s+(?:forte|muito|insuport[aá]vel)\b/i,
    /\binfarto\b/i,

    # Neurológica
    /\b(?:convuls[aã]o|convulsionou|convulsionando|crise\s+convulsiva)\b/i,
    /\btendo\s+convuls(?:[aã]o|[oõ]es)\b/i,
    /\b(?:AVC|derrame|acidente\s+vascular)\b/i,

    # Anafilaxia
    /\b(?:anafilaxia|choque\s+anaf[ií]l[aá]tico)\b/i,
    /\brea[cç][aã]o\s+al[eé]rgica\s+(?:grave|forte)\b/i,
    /\binchando\s+(?:o\s+rosto|a\s+garganta|os\s+l[aá]bios|a\s+l[ií]ngua)\b/i,

    # Tóxico
    /\b(?:envenenamento|intoxica[cç][aã]o|envenenad[oa])\b/i,

    # Pediatria — febre alta + bebê/criança/recém-nascido (qualquer
    # ordem). Duas regexes em vez de lookahead pra a captura ($~)
    # carregar o trecho real, não vazio.
    /\bf[eé]bre\s+(?:muito\s+)?alta\b.{0,80}?\b(?:beb[eê]|crian[cç]a|rec[eé]m[\s-]nascid[oa]|filho\s+pequeno|filha\s+pequena)\b/im,
    /\b(?:beb[eê]|crian[cç]a|rec[eé]m[\s-]nascid[oa]|filho\s+pequeno|filha\s+pequena)\b.{0,80}?\bf[eé]bre\s+(?:muito\s+)?alta\b/im
  ].freeze

  # ─── Sangramento — contexto-sensível ──────────────────────────
  # Numa clínica ODONTOLÓGICA "muito sangue"/"sangrando" quase sempre é
  # gengiva/dente: urgência dentária, resolvida numa avaliação — NÃO caso
  # de SAMU. Por isso sangramento só vira emergência clínica quando NÃO há
  # contexto bucal na mensagem. Demais emergências (respiração, coração,
  # neuro, anafilaxia, suicídio) disparam sempre, com ou sem contexto bucal.
  BLEEDING_PATTERNS = [
    /\bsangra(?:mento|ndo)\s+(?:muito|intenso|forte|sem\s+parar|n[aã]o\s+para|demais|grave)\b/i,
    /\b(?:hemorragia|muito\s+sangue)\b/i,
    /\bperdendo\s+(?:muito\s+)?sangue\b/i
  ].freeze

  ORAL_CONTEXT = Regexp.union(
    /\b(?:dente|dentes|dental|odonto\w*|gengiv\w*|boca|bucal|bruxismo)\b/i,
    /\b(?:mordida|canal|extra[cç][aã]o|siso|c[aá]rie|restaura[cç][aã]o)\b/i,
    /\b(?:aparelho|implante|pr[oó]tese|l[ií]ngua)\b/i
  )

  # ─── Ideação suicida → CVV 188 ────────────────────────────────
  SUICIDAL_PATTERNS = [
    /\bquero\s+morrer\b/i,
    /\bquerendo\s+morrer\b/i,
    /\bn[aã]o\s+quero\s+(?:mais\s+)?viver\b/i,
    /\bn[aã]o\s+vejo\s+sentido\s+em\s+viver\b/i,

    # "vou me matar" / "quero me matar" — exclui "matar de rir/tanto"
    /\b(?:vou|quero|querendo|pensando\s+em)\s+me\s+matar\b(?!\s+de\s+(?:rir|tanto|fome|raiva))/i,
    /\bme\s+matando\b/i,

    # Wildcard suicid* (suicídio, suicida, suicidar)
    /\bsuic[ií]d/i,

    # Tirar a vida / acabar com a vida
    /\bacabar\s+com\s+(?:tudo|a\s+minha\s+vida|minha\s+vida)\b/i,
    /\b(?:quero\s+|vou\s+)?tirar\s+(?:a\s+)?minha\s+vida\b/i,
    /\bdar\s+fim\s+(?:[aà]\s+)?(?:minha\s+)?vida\b/i,
    /\bp[oô]r\s+um\s+fim\s+(?:em\s+tudo|nisso\s+tudo|na\s+minha\s+vida)\b/i,

    # Auto-mutilação séria (não confundir com "me machuquei jogando bola")
    /\bquer(?:o|er|endo)\s+me\s+machucar\b/i,
    /\bme\s+machucar\s+(?:de\s+verdade|s[eé]rio|a\s+s[eé]rio)\b/i
  ].freeze

  def initialize(message)
    @text = message.to_s
  end

  def call
    # Ideação suicida tem prioridade — categoria diferente, mensagem
    # diferente (CVV em vez de SAMU). Em mensagens raríssimas que
    # batem nas duas categorias, melhor mandar CVV: emergência clínica
    # genérica também aceita "vou avisar a equipe", mas CVV é específico.
    return Match.new(category: :suicidal, keyword: $LAST_MATCH_INFO.to_s) if SUICIDAL_PATTERNS.any? { |re| @text =~ re }
    return Match.new(category: :clinical, keyword: $LAST_MATCH_INFO.to_s) if CLINICAL_PATTERNS.any? { |re| @text =~ re }

    # Sangramento só é emergência (SAMU) se NÃO houver contexto bucal —
    # gengiva sangrando / dente quebrado é urgência dentária, não SAMU.
    return Match.new(category: :clinical, keyword: 'sangramento_nao_bucal') if bleeding_emergency?

    nil
  end

  private

  def bleeding_emergency?
    BLEEDING_PATTERNS.any? { |re| @text =~ re } && @text !~ ORAL_CONTEXT
  end
end
