# Projeto "Tom de voz da Bea" — Fase 2 (geração).
#
# Redige nomes de pessoas → `[nome]` nos textos do perfil de estilo (LGPD). O
# PiiRedactor mascara CPF/telefone/email mas NÃO nomes; nos exemplos few-shot o
# nome de UM paciente real iria pro prompt de TODOS.
#
# Best-effort em DUAS frentes (a revisão humana na aprovação é o backstop pro
# resíduo — typo de saudação, nome no meio da frase):
#   1. VOCATIVO: nome capitalizado logo após saudação/agradecimento
#      ("Bom dia Nancy", "Perfeito Natalia") — pega mesmo sem contato salvo nem
#      ajuda do LLM, que é o caso mais comum em WhatsApp de clínica.
#   2. LISTA CONHECIDA: tokens do `sender` das falas PACIENTE (quando o contato
#      está salvo com nome) + nomes que o LLM detectar — redige onde aparecerem.
class AiAgent::StyleProfile::NameRedactor
  MIN_NAME_LEN = 3 # ignora preposições "de"/"da"/"do" ao tokenizar
  WORD_RE = /\p{L}+/
  NAME_TOKEN_RE = /\A\p{L}{#{MIN_NAME_LEN},}\z/

  # Trigger de saudação/agradecimento case-insensitive via (?i:...); o nome
  # logo após fica case-SENSITIVE (\p{Lu}) pra exigir capitalização e não
  # mascarar palavra comum minúscula ("bom dia tudo").
  VOCATIVE_RE = /
    ((?i:bom\s+dia|boa\s+tarde|boa\s+noite|oi+|ol[áa]+|opa|obrigad[oa]|imagina|perfeito|prezad[oa]|car[oa])[ ,]+)
    (\p{Lu}\p{L}+)/x

  # Palavras comuns capitalizadas que aparecem após saudação mas NÃO são nome de
  # paciente — evita super-redação ("Oi Dra", "Boa tarde Tudo bem").
  VOCATIVE_STOPWORDS = %w[dra dr doutor doutora tudo sim claro certo bom boa beleza obrigada obrigado].freeze

  def initialize(raw_names)
    @tokens = Array(raw_names)
              .flat_map { |name| name.to_s.split(/\s+/) }
              .filter_map { |token| token.downcase if token.match?(NAME_TOKEN_RE) }
              .uniq
  end

  def redact(text)
    redact_tokens(redact_vocative(text.to_s))
  end

  private

  def redact_vocative(text)
    text.gsub(VOCATIVE_RE) do
      lead = Regexp.last_match(1)
      name = Regexp.last_match(2)
      VOCATIVE_STOPWORDS.include?(name.downcase) ? "#{lead}#{name}" : "#{lead}[nome]"
    end
  end

  def redact_tokens(text)
    return text if @tokens.empty?

    text.gsub(WORD_RE) do |word|
      word.match?(/\A\p{Lu}/) && @tokens.include?(word.downcase) ? '[nome]' : word
    end
  end
end
