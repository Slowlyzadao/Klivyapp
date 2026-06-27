# Classifica se um turno da Bea é "high-stakes" — onde erro custa
# caro (compromisso real na agenda, alegação clínica errada, valor
# de procedimento invalido, info da clínica). Determinístico,
# zero LLM. Usado pelo Sentinel pra decidir se vale rodar Reflection.
#
# Heurística:
#   - Tool calls executadas no turno: book/reschedule/cancel,
#     clinic_info, financial_status → high-stakes.
#   - Resposta menciona valor monetário (R$, "centavos", número
#     com vírgula seguido de "reais") → high-stakes.
#   - Resposta menciona tema clínico forte (medicamento, dosagem,
#     diagnóstico, contraindicação) → high-stakes.
#
# Senão → low-stakes (saudação, pergunta de horário, papo geral).
class AiAgent::Humanization::HighStakesDetector
  Reason = Struct.new(:high_stakes, :categories, keyword_init: true) do
    def high_stakes? = high_stakes
  end

  HIGH_STAKES_TOOLS = %w[
    book_appointment
    reschedule_appointment
    cancel_appointment
    clinic_info
    financial_status
    erasure_request
  ].freeze

  MONEY_REGEX = /\b(?:R\$|reais|valor|preço|preco|custa|custo|investimento|centavos)\b/i
  CLINICAL_REGEX = /\b(?:medicament|rem[ée]di[oa]|dosagem|posologia|prescri[cç][aã]o|receita|contraindica|diagn[oó]stic|sintoma|alergi|anest[ée]si|antibi[oó]tic|infl[au]ma[cç][aã]o|infec[cç][aã]o|sangrament|hemorragia|urg[eê]ncia|emerg[eê]ncia|dor\s+de\s+\w|febre|infec[cç]\w*|inflama[cç]\w*|c[áa]rie|abscesso|pus)\w*/i

  def initialize(response_text:, tool_log: [])
    @response = response_text.to_s
    @tools = Array(tool_log)
  end

  def call
    cats = []
    cats << 'tool_action' if used_high_stakes_tool?
    cats << 'monetary' if MONEY_REGEX.match?(@response)
    cats << 'clinical' if CLINICAL_REGEX.match?(@response)

    Reason.new(high_stakes: cats.any?, categories: cats)
  end

  private

  def used_high_stakes_tool?
    @tools.any? do |t|
      name = (t[:name] || t['name']).to_s
      HIGH_STAKES_TOOLS.include?(name)
    end
  end
end
