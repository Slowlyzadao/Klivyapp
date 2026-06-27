module Financial
  module Concerns
    # Helpers para atributos monetários armazenados em centavos (BIGINT).
    # Canon Parte 6 §"Valores em centavos".
    #
    # Uso:
    #   class Budget < Financial::ApplicationRecord
    #     extend Financial::Concerns::MoneyAttribute::ClassMethods
    #     money_attribute :total_cents, as: :total
    #   end
    #
    # Permite ler/escrever em "reais" (BigDecimal) sem perder precisão.
    module MoneyAttribute
      extend ActiveSupport::Concern

      class_methods do
        # Define um par read/write reais ↔ centavos para a coluna _cents informada.
        def money_attribute(cents_column, as:)
          define_method(as) do
            cents = read_attribute(cents_column)
            return nil if cents.nil?

            BigDecimal(cents) / 100
          end

          define_method("#{as}=") do |value|
            if value.nil?
              write_attribute(cents_column, nil)
            elsif value.is_a?(Integer)
              # Convenção: Integer SEMPRE é tratado como centavos quando a coluna é _cents
              write_attribute(cents_column, value)
            else
              decimal = value.is_a?(BigDecimal) ? value : BigDecimal(value.to_s)
              write_attribute(cents_column, (decimal * 100).round.to_i)
            end
          end
        end
      end

      # Distribui o resto na ÚLTIMA parcela. Canon Parte 6:
      # "R$ 920 ÷ 3 = R$ 306,66 + R$ 306,66 + R$ 306,68"
      #
      # Financial::Concerns::MoneyAttribute.split(92000, 3)
      # => [30666, 30666, 30668]
      def self.split(total_cents, count)
        raise ArgumentError, 'count must be > 0' if count <= 0
        return [total_cents] if count == 1

        base = total_cents / count
        remainder = total_cents - (base * count)
        Array.new(count - 1, base) + [base + remainder]
      end

      # Formata BigDecimal em pt-BR. Frontend deve fazer isso preferencialmente
      # via Intl.NumberFormat, mas back precisa para PDFs e e-mails.
      def self.format_brl(decimal_or_cents)
        decimal = decimal_or_cents.is_a?(Integer) ? BigDecimal(decimal_or_cents) / 100 : decimal_or_cents
        format('R$ %s', sprintf_brl(decimal))
      end

      def self.sprintf_brl(decimal)
        formatted = sprintf('%.2f', decimal.to_f)
        integer_part, decimal_part = formatted.split('.')
        integer_part = integer_part.reverse.scan(/\d{1,3}/).join('.').reverse
        "#{integer_part},#{decimal_part}"
      end
    end
  end
end
