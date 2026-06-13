# Normaliza identifier (phone E.164 ou email) para busca consistente.
# PRD §5.4: "Telefone deve estar no formato E.164. Backend normaliza antes de buscar."
module PatientPortal
  class IdentifierNormalizer
    EMAIL_REGEX = /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/.freeze

    class << self
      def call(value)
        v = value.to_s.strip
        return [:email, v.downcase] if v.match?(EMAIL_REGEX)

        digits = v.gsub(/\D/, '')
        return [:phone, "+#{digits}"] if digits.length >= 10

        [:unknown, v]
      end
    end
  end
end
