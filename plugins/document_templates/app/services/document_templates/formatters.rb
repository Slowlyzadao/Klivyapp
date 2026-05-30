# frozen_string_literal: true

module DocumentTemplates
  # Formatadores aplicados aos valores resolvidos pelas variáveis.
  #
  # Cada formatter recebe o valor cru (string, Date, Integer, etc.) e
  # retorna string formatada pro PDF. Sempre defensivos: blank → blank,
  # tipo errado → valor original.
  module Formatters
    module_function

    def apply(value, formatter)
      return value if value.blank? || formatter.blank?

      case formatter.to_sym
      when :cpf         then cpf(value)
      when :cnpj        then cnpj(value)
      when :phone       then phone(value)
      when :cep         then cep(value)
      when :date_short  then date_short(value)
      when :date_long   then date_long(value)
      when :age         then age(value)
      when :currency    then currency(value)
      when :uppercase   then value.to_s.upcase
      when :image_tag   then image_tag(value)
      else value
      end
    end

    # 12345678900 → 123.456.789-00
    def cpf(value)
      digits = value.to_s.gsub(/\D/, '')
      return value.to_s if digits.length != 11

      "#{digits[0..2]}.#{digits[3..5]}.#{digits[6..8]}-#{digits[9..10]}"
    end

    # 12345678000190 → 12.345.678/0001-90
    def cnpj(value)
      digits = value.to_s.gsub(/\D/, '')
      return value.to_s if digits.length != 14

      "#{digits[0..1]}.#{digits[2..4]}.#{digits[5..7]}/#{digits[8..11]}-#{digits[12..13]}"
    end

    # 11987654321 → (11) 98765-4321 ; 1133003000 → (11) 3300-3000
    def phone(value)
      digits = value.to_s.gsub(/\D/, '')
      case digits.length
      when 11 then "(#{digits[0..1]}) #{digits[2..6]}-#{digits[7..10]}"
      when 10 then "(#{digits[0..1]}) #{digits[2..5]}-#{digits[6..9]}"
      else value.to_s
      end
    end

    # 01310100 → 01310-100
    def cep(value)
      digits = value.to_s.gsub(/\D/, '')
      return value.to_s if digits.length != 8

      "#{digits[0..4]}-#{digits[5..7]}"
    end

    def date_short(value)
      date = coerce_date(value)
      return value.to_s if date.nil?

      I18n.l(date, format: :default, locale: :'pt_BR')
    rescue I18n::MissingTranslationData, I18n::InvalidLocaleData
      date.strftime('%d/%m/%Y')
    end

    def date_long(value)
      date = coerce_date(value)
      return value.to_s if date.nil?

      I18n.l(date, format: :long, locale: :'pt_BR')
    rescue I18n::MissingTranslationData, I18n::InvalidLocaleData
      date.strftime('%d de %B de %Y')
    end

    # Aceita Date, DateTime ou Integer (idade já calculada).
    def age(value)
      return "#{value} anos" if value.is_a?(Integer)

      date = coerce_date(value)
      return value.to_s if date.nil?

      today = Date.current
      years = today.year - date.year
      years -= 1 if today < date + years.years
      "#{years} anos"
    end

    def currency(value)
      return value.to_s unless value.is_a?(Numeric)

      ActiveSupport::NumberHelper.number_to_currency(value, unit: 'R$', separator: ',', delimiter: '.')
    end

    # Renderiza tag <img> em vez de texto. Usado pelos campos de logo da
    # clínica e assinatura do profissional. URL é escapada pra evitar XSS.
    def image_tag(url)
      return '' if url.blank?

      safe = ERB::Util.html_escape(url.to_s)
      %(<img src="#{safe}" alt="" />)
    end

    def coerce_date(value)
      case value
      when Date, DateTime, Time then value.to_date
      when String then Date.parse(value)
      else nil
      end
    rescue ArgumentError, TypeError
      nil
    end
  end
end
