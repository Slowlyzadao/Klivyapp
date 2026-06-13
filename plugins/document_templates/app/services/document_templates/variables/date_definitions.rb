# frozen_string_literal: true

module DocumentTemplates
  module Variables
    # Variáveis da categoria DATA/HORA — calculadas no momento da geração
    # do documento. Não precisam de banco, só de Time.current + I18n pt-BR.
    module DateDefinitions
      LIST = [
        { key: 'date.today',       label: 'Data de hoje',       example: '26/05/2026',          formatter: :date_short },
        { key: 'date.today_long',  label: 'Data por extenso',   example: '26 de maio de 2026',  formatter: :date_long },
        { key: 'date.day',         label: 'Dia',                example: '26' },
        { key: 'date.day_padded',  label: 'Dia (2 dígitos)',    example: '26' },
        { key: 'date.month',       label: 'Mês (nome)',         example: 'maio' },
        { key: 'date.month_number', label: 'Mês (número)',      example: '5' },
        { key: 'date.year',        label: 'Ano',                example: '2026' },
        { key: 'date.day_of_week', label: 'Dia da semana',      example: 'terça-feira' },
        { key: 'date.city_today',  label: 'Cidade, data por extenso', example: 'São Paulo, 26 de maio de 2026' },
        { key: 'date.time',        label: 'Hora atual',         example: '14:30' },
        { key: 'date.datetime',    label: 'Data + hora',        example: '26/05/2026 14:30' }
      ].map { |attrs| DocumentTemplates::Variable.new(category: 'Data', **attrs) }.freeze
    end
  end
end
