# frozen_string_literal: true

module DocumentTemplates
  module Seeds
    # Popula (ou atualiza) a biblioteca Klivy global de templates.
    #
    # **Idempotente**: usa `find_or_create_by` com chave estável
    # `(name, source='klivy', account_id: nil, document_type)`. Re-rodar é
    # seguro — não duplica. Quando o JSON do template muda no código, o
    # seed atualiza `content_json` da row Klivy existente (e bumpa version).
    #
    # Como rodar:
    #   bin/rails runner 'DocumentTemplates::Seeds::LibrarySeeder.call!'
    #
    # Ou via rake task (lib/tasks/document_templates.rake):
    #   bundle exec rake document_templates:seed_klivy_library
    class LibrarySeeder
      def self.call!(verbose: true)
        new(verbose: verbose).run
      end

      def initialize(verbose: true)
        @verbose = verbose
        @stats = { created: 0, updated: 0, skipped: 0 }
      end

      def run
        log "Seeding Klivy template library..."

        all_definitions.each do |definition|
          seed_one(definition)
        end

        log "Done. created=#{@stats[:created]} updated=#{@stats[:updated]} skipped=#{@stats[:skipped]}"
        @stats
      end

      private

      def all_definitions
        ClinicalTemplates.all + ConsentTemplates.all
      end

      def seed_one(definition)
        template = DocumentTemplate.find_or_initialize_by(
          name: definition[:name],
          source: 'klivy',
          account_id: nil,
          document_type: definition[:document_type]
        )

        new_content = definition[:content_json]

        if template.new_record?
          template.content_json = new_content
          template.status = 'active'
          template.paper_size = 'A4'
          template.orientation = 'portrait'
          template.created_by_user_id = nil
          template.description = build_description(definition)
          template.save!
          @stats[:created] += 1
          log "  + created: #{template.name} (#{template.document_type})"
        elsif content_changed?(template, new_content)
          # Content mudou — atualiza (version sobe automaticamente via callback).
          template.content_json = new_content
          template.description = build_description(definition)
          template.save!
          @stats[:updated] += 1
          log "  ~ updated: #{template.name} (#{template.document_type}, v#{template.version})"
        else
          @stats[:skipped] += 1
          log "  · skipped (unchanged): #{template.name}"
        end
      end

      # JSONB do Postgres devolve keys como Strings e arrays/hashes em ordem
      # estável. `new_content` (montado via Builder em Ruby) também usa
      # String keys. Comparação estrutural com `==` é suficiente — não usar
      # `.to_json` pois pode produzir strings diferentes pra Hashes
      # estruturalmente idênticos com ordem de keys diferente.
      def content_changed?(template, new_content)
        normalize(template.content_json) != normalize(new_content)
      end

      # Normaliza pra comparação: força String keys recursivamente.
      def normalize(node)
        case node
        when Hash  then node.each_with_object({}) { |(k, v), h| h[k.to_s] = normalize(v) }
        when Array then node.map { |v| normalize(v) }
        else node
        end
      end

      def build_description(_definition)
        'Modelo Klivy padrão. Clique em "Usar este modelo" pra clonar pra sua clínica e editar.'
      end

      def log(msg)
        return unless @verbose

        Rails.logger.info("[DocumentTemplates::Seeds] #{msg}")
        puts msg if defined?(Rails::Console) || ENV['VERBOSE_SEEDS']
      end
    end
  end
end
