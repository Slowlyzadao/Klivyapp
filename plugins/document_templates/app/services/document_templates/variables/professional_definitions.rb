# frozen_string_literal: true

module DocumentTemplates
  module Variables
    # Variáveis da categoria PROFISSIONAL.
    #
    # "Profissional" = o User logado que está gerando o documento (não um
    # campo do paciente). Campos institucionais (CRM, especialidade,
    # assinatura escaneada) vivem em `user.custom_attributes` JSONB — User
    # não tem colunas dedicadas (auditado 2026-05-27).
    module ProfessionalDefinitions
      LIST = [
        { key: 'professional.name',           label: 'Nome',            example: 'Dr. Carlos Andrade' },
        { key: 'professional.display_name',   label: 'Nome de exibição', example: 'Dr. Carlos' },
        { key: 'professional.email',          label: 'E-mail',          example: 'carlos@clinica.com' },

        # Conselho profissional — campos em user.custom_attributes.
        # Ex: { 'council_acronym' => 'CRM', 'council_number' => '123456', 'council_state' => 'SP' }
        { key: 'professional.council_acronym', label: 'Conselho (sigla)',  example: 'CRM' },
        { key: 'professional.council_number',  label: 'Nº do conselho',    example: '123456' },
        { key: 'professional.council_state',   label: 'UF do conselho',    example: 'SP' },
        { key: 'professional.council_full',    label: 'Conselho completo', example: 'CRM/SP 123456' },

        { key: 'professional.specialty', label: 'Especialidade', example: 'Dermatologia' },

        # Imagem de assinatura escaneada cadastrada nas preferências do profissional.
        # Não confundir com assinatura eletrônica (Clicksign — Fase 5).
        { key: 'professional.signature_image_url', label: 'Assinatura (imagem)', example: '<img>', formatter: :image_tag }
      ].map { |attrs| DocumentTemplates::Variable.new(category: 'Profissional', **attrs) }.freeze
    end
  end
end
