# frozen_string_literal: true

module DocumentTemplates
  # Plugin de templates de documentos — editor visual (TipTap no front) com
  # variáveis dinâmicas, biblioteca Klivy de modelos e geração de PDF via
  # Grover (HTML→Chromium headless).
  #
  # Decisão arquitetural: sem `isolate_namespace` (mesmo padrão de telemed,
  # patient_portal e agenda). Models vivem no namespace global
  # (`DocumentTemplate`, `DocumentTemplateFolder`); services/jobs/policies em
  # `module DocumentTemplates`. Engine só serve pra autoload do diretório e
  # injetar associações/concerns no core via `to_prepare`.
  class Engine < ::Rails::Engine
    engine_name 'document_templates'

    # Rake tasks do plugin (lib/tasks/document_templates.rake).
    rake_tasks do
      load File.expand_path('../tasks/document_templates.rake', __dir__)
    end

    # Injeta as associações inversas e o concern de extensão. Roda a cada
    # reload em desenvolvimento, uma vez em produção.
    config.to_prepare do
      # Account ─ has_many pros templates próprios e pastas.
      # NOTA: templates Klivy globais (account_id NULL) NÃO aparecem aqui.
      if defined?(Account)
        Account.class_eval do
          has_many :document_templates,        dependent: :destroy_async
          has_many :document_template_folders, dependent: :destroy_async
        end
      end

      # Document e ConsentRecord ganham `document_template_id`,
      # `rendered_html`, `pdf_hash` (apenas Document) e o helper
      # `#generated_from_template?` via concern.
      Document.include(DocumentTemplateExtension)        if defined?(Document)
      ConsentRecord.include(DocumentTemplateExtension)   if defined?(ConsentRecord)
    end
  end
end
