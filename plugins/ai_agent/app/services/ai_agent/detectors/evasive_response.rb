# Detecta se a Bea respondeu evasivamente — frases tipo "vou checar com
# a equipe", "preciso confirmar com a clínica", "não tenho essa info".
# São sinais legítimos de "não sei", mas se acontecem 3+ vezes seguidas
# com o MESMO paciente, é hora da equipe revisar a base de conhecimento.
#
# Conservador: só conta evasiva pura (frases que indicam "alguém precisa
# responder" ou "não sei"). Não conta resposta normal de handoff
# ("vou te transferir") porque handoff é o caminho certo, não falha.
class AiAgent::Detectors::EvasiveResponse
  EVASIVE_PATTERNS = [
    /\bvou\s+(?:checar|verificar|confirmar|conferir|perguntar|consultar)\s+(?:com|na?)\s+(?:a\s+)?(?:equipe|cl[ií]nica|recep[cç][aã]o|secretaria|pessoal)/i,
    /\bdeixa\s+eu\s+(?:checar|verificar|confirmar|conferir|consultar)\s+(?:com|na?)?\s*(?:a\s+)?(?:equipe|cl[ií]nica|recep[cç][aã]o|pessoal)/i,
    /\b(?:preciso|tenho\s+que)\s+(?:checar|verificar|confirmar|consultar|perguntar)\s+(?:com|na?)\s+(?:a\s+)?(?:equipe|cl[ií]nica|recep[cç][aã]o|pessoal)/i,
    /\bn[aã]o\s+(?:tenho|sei|encontrei)\s+(?:essa|esta)?\s*informa[cç][aã]o/i,
    /\b(?:vou|posso)\s+(?:repassar|encaminhar)\s+(?:pra|para)\s+(?:o\s+)?(?:time|equipe|recep[cç][aã]o)/i,
    /\bn[aã]o\s+consigo\s+(?:te\s+)?(?:responder|informar|dar)\s+(?:isso|essa\s+informa[cç][aã]o)/i,
    /\bn[aã]o\s+sei\s+te\s+(?:dizer|informar|responder)\s+(?:isso|essa)/i
  ].freeze

  def initialize(message)
    @text = message.to_s
  end

  def evasive?
    EVASIVE_PATTERNS.any? { |re| @text =~ re }
  end
end
