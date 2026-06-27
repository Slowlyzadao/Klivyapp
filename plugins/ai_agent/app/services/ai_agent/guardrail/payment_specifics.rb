# Rede de segurança determinística contra INVENÇÃO de condições de FINANCIAMENTO.
#
# Ao quebrar objeção de dinheiro/preço (regra de ouro 11 do prompt), a Bea
# consulta a RAG e deve falar de parcelamento só de forma GENÉRICA. O material
# da clínica é genérico ("parcelar em condições que não pesem"), mas o
# Gemini-flash tem um prior forte de clínica odontológica e, em ~1 a cada 6
# turnos, carimba um termo ESPECÍFICO que não existe no material — ex.: "em até
# 8x sem juros no cartão de crédito". Isso é uma promessa que a clínica pode não
# honrar; regra de prompt não segura 100% (modelo estocástico).
#
# ESCOPO (decisão do dono, 2026-06-23): hoje NÃO existe configuração de
# pagamento por clínica (é feature futura). Sem essa fonte de verdade, QUALQUER
# parcela/juros específico que a Bea diga é invenção → generaliza para a forma
# neutra. Quando a config de pagamento por clínica existir, ela vira a fonte que
# autoriza termos específicos (passar `account` já está previsto na assinatura).
#
# DELIBERADAMENTE NÃO toca em valores "R$ ..." (preço pode vir legítimo do
# clinic_info) nem em formas de pagamento isoladas — só em FINANCIAMENTO
# (nº de parcelas, juros), que foi o que a Bea inventou na prática.
#
# Mesma família de guardrails pós-LLM de [[AiAgent::Guardrail::ReasoningLeak]]:
# mexe SÓ no texto final, nunca re-executa tools.
module AiAgent::Guardrail::PaymentSpecifics
  GENERIC = 'em condições facilitadas'.freeze

  # Parcelamento com número (consome "sem juros" e "no cartão" acoplados):
  # "em até 8x sem juros no cartão de crédito", "em 12 vezes", "6 parcelas",
  # "parcelado em 10x". Modo /x (free-spacing) só pra caber na linha — os
  # espaços do padrão são todos \s explícitos.
  INSTALLMENT = /
    \b(?:parcelad[oa]\s+)?
    (?:em\s+at[ée]\s+|em\s+)?
    \d+\s*(?:x|vezes|parcelas)\b
    (?:\s+sem\s+juros)?
    (?:\s+(?:no|via|pelo)\s+cart[ãa]o(?:\s+de\s+cr[ée]dito)?)?
  /ix
  PERCENT_INTEREST = /\b\d+\s*%\s*(?:de\s+)?juros(?:\s+ao\s+(?:m[êe]s|ano))?/i
  NO_INTEREST = /\bsem\s+juros\b/i

  DETECT = Regexp.union(INSTALLMENT, PERCENT_INTEREST, NO_INTEREST)

  # `account` fica na assinatura pra futura config de pagamento por clínica
  # (autorizaria termos específicos). Hoje não é usado: generaliza incondicional.
  def self.sanitize(text:, account: nil)
    _ = account
    s = text.to_s
    return s if s.strip.empty? || !s.match?(DETECT)

    out = s.gsub(INSTALLMENT, GENERIC)
    out = out.gsub(PERCENT_INTEREST, GENERIC)
    out = out.gsub(NO_INTEREST, '')
    cleanup(out)
  end

  # Conserta espaços/pontuação órfãos deixados pelas remoções por vazio.
  def self.cleanup(str)
    str.gsub(/\s{2,}/, ' ')
       .gsub(/\s+([.,!?;:])/, '\1')
       .strip
  end
end
