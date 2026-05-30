# frozen_string_literal: true

module DocumentTemplates
  module Readers
    # Lê valores brutos pra chaves `date.*`.
    #
    # `now` é injetado pelo Resolver — em produção é Time.current, em testes
    # pode ser congelado pra previsibilidade. `city` vem do endereço da
    # clínica (pra montar 'São Paulo, 26 de maio de 2026').
    class DateReader
      def initialize(now:, city: nil)
        @now = now
        @city = city
      end

      def read(key)
        case key
        when 'date.today',     'date.today_long' then @now.to_date
        when 'date.day'           then @now.day.to_s
        when 'date.day_padded'    then format('%02d', @now.day)
        when 'date.month'         then month_name(@now)
        when 'date.month_number'  then @now.month.to_s
        when 'date.year'          then @now.year.to_s
        when 'date.day_of_week'   then day_of_week_name(@now)
        when 'date.city_today'    then city_today
        when 'date.time'          then @now.strftime('%H:%M')
        when 'date.datetime'      then @now.strftime('%d/%m/%Y %H:%M')
        end
      end

      private

      def month_name(time)
        I18n.l(time.to_date, format: '%B', locale: :'pt_BR').downcase
      rescue I18n::MissingTranslationData, I18n::InvalidLocaleData
        time.strftime('%B').downcase
      end

      def day_of_week_name(time)
        I18n.l(time.to_date, format: '%A', locale: :'pt_BR').downcase
      rescue I18n::MissingTranslationData, I18n::InvalidLocaleData
        time.strftime('%A').downcase
      end

      def city_today
        long_date = begin
          I18n.l(@now.to_date, format: :long, locale: :'pt_BR')
        rescue I18n::MissingTranslationData, I18n::InvalidLocaleData
          @now.strftime('%d de %B de %Y')
        end
        return long_date if @city.blank?

        "#{@city}, #{long_date}"
      end
    end
  end
end
