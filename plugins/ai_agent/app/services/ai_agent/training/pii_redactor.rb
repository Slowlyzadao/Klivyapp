# Estágio 1 — Redação de PII (LGPD). Mascara CPF, CNPJ, e-mail, telefone e
# CEP antes de QUALQUER dado sair para uma API externa. NÃO mascara valores
# em reais nem horários — preço e horário são conhecimento que a Bea precisa.
class AiAgent::Training::PiiRedactor
  EMAIL = /[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/i
  CNPJ  = %r{\b\d{2}\.?\d{3}\.?\d{3}/?\d{4}-?\d{2}\b}
  CPF   = /\b\d{3}\.?\d{3}\.?\d{3}-?\d{2}\b/
  CEP   = /\b\d{5}-\d{3}\b/
  # Telefone BR: +55 opcional, DDD, 8-9 dígitos, separadores livres. Os
  # lookarounds evitam casar pedaços de horário (HH:MM) ou números maiores.
  PHONE = /(?<![\d:])(?:\+?55\s?)?\(?\d{2}\)?[\s.-]?9?\d{4}[\s.-]?\d{4}(?![\d:])/

  # Ordem importa: e-mail e CNPJ (mais longos) antes de CPF; telefone por
  # último por ser o mais ganancioso.
  MASKS = {
    EMAIL => '[email]',
    CNPJ => '[cnpj]',
    CPF => '[cpf]',
    CEP => '[cep]',
    PHONE => '[telefone]'
  }.freeze

  def self.call(text)
    return text if text.blank?

    MASKS.reduce(text) { |acc, (regex, mask)| acc.gsub(regex, mask) }
  end
end
