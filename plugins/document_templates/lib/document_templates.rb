# frozen_string_literal: true

# Entry point do plugin document_templates. Carregado automaticamente pelo
# Rails via glob em config/application.rb (`plugins/*/lib/*/engine.rb`).
# Mantém só o require do engine; toda lógica vive em app/.

require 'document_templates/engine'

module DocumentTemplates
end
