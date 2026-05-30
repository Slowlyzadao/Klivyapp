# frozen_string_literal: true

module DocumentTemplates
  module Variables
    # Variáveis da categoria CLÍNICA.
    #
    # Mapeamento com schema real (auditado 2026-05-27): Account NÃO tem
    # colunas dedicadas pra CNPJ, endereço, telefone — tudo vive em
    # `custom_attributes` JSONB ou `settings` JSONB. O Resolver lê com
    # fallback gracioso quando o campo está vazio (não quebra geração).
    module ClinicDefinitions
      LIST = [
        { key: 'clinic.name',          label: 'Nome da clínica',  example: 'Clínica Bem Estar' },
        { key: 'clinic.fantasy_name',  label: 'Nome fantasia',    example: 'Bem Estar Estética' },
        { key: 'clinic.cnpj',          label: 'CNPJ',             example: '12.345.678/0001-90', formatter: :cnpj },

        { key: 'clinic.address_full',   label: 'Endereço completo', example: 'Av. Paulista, 1000, Sala 100, Bela Vista, São Paulo-SP, 01310-100' },
        { key: 'clinic.address_street', label: 'Logradouro',        example: 'Av. Paulista, 1000' },
        { key: 'clinic.address_city',   label: 'Cidade',            example: 'São Paulo' },
        { key: 'clinic.address_state',  label: 'Estado (UF)',       example: 'SP' },
        { key: 'clinic.address_zip',    label: 'CEP',               example: '01310-100', formatter: :cep },

        { key: 'clinic.phone',   label: 'Telefone',  example: '(11) 3000-3000', formatter: :phone },
        { key: 'clinic.email',   label: 'E-mail',    example: 'contato@bemestar.com' },
        { key: 'clinic.website', label: 'Site',      example: 'bemestar.com.br' },

        # `:image_tag` é especial — não substitui por texto, renderiza
        # `<img src="...">` no HTML final (lógica no Renderer da Fase 3).
        { key: 'clinic.logo_url', label: 'Logo (imagem)', example: '<img>', formatter: :image_tag }
      ].map { |attrs| DocumentTemplates::Variable.new(category: 'Clínica', **attrs) }.freeze
    end
  end
end
