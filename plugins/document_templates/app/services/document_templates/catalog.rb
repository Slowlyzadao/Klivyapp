# frozen_string_literal: true

module DocumentTemplates
  # Catálogo de variáveis disponíveis pra inserção nos templates.
  #
  # Decisão (plano §2.8): catálogo vive em CÓDIGO, não em banco. Justificativa:
  #   - Não tem CRUD pelo usuário (clínica não cria variável customizada no MVP).
  #   - Resolução do valor exige código de qualquer jeito (lookup → método).
  #   - Versionamento via git (mudanças passam por review).
  #   - Atualização não exige migration.
  #
  # As definições estão divididas por categoria em arquivos
  # `app/services/document_templates/variables/<categoria>_definitions.rb`
  # pra evitar "arquivo deus" — cada categoria gerencia sua própria lista.
  #
  # Lazy-load via `@all ||=` pra não tocar nas constantes de definição
  # antes do Zeitwerk ter carregado tudo.
  module Catalog
    class << self
      def all
        @all ||= [
          Variables::PatientDefinitions::LIST,
          Variables::ClinicDefinitions::LIST,
          Variables::ProfessionalDefinitions::LIST,
          Variables::DateDefinitions::LIST
        ].flatten.freeze
      end

      def by_key
        @by_key ||= all.index_by(&:key).freeze
      end

      def find(key)
        by_key[key.to_s]
      end

      def find!(key)
        find(key) || raise(ArgumentError, "Unknown variable key: #{key.inspect}")
      end

      def categories
        all.map(&:category).uniq
      end

      # Versão usada pelo endpoint público (frontend popula o menu de inserção).
      def for_frontend
        all.map(&:to_public_hash)
      end

      # Versão agrupada por categoria — usada no UI pra mostrar o menu de "/"
      # com seções dobráveis (👤 Paciente, 🏥 Clínica, 👨‍⚕️ Profissional, 📅 Data).
      def grouped_for_frontend
        for_frontend.group_by { |v| v[:category] }
      end
    end
  end
end
