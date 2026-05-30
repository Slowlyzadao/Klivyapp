# frozen_string_literal: true

# Rake tasks do plugin document_templates.
#
# Pra Rails descobrir automaticamente os .rake do plugin, adicionei o path
# em config.paths via engine.rb (config.paths['lib/tasks']). Sem isso, só
# `bin/rails runner 'DocumentTemplates::Seeds::LibrarySeeder.call!'` funciona.

namespace :document_templates do
  desc 'Popula (ou atualiza) a biblioteca Klivy global de templates (idempotente).'
  task seed_klivy_library: :environment do
    ENV['VERBOSE_SEEDS'] = 'true' # força logs no console
    stats = DocumentTemplates::Seeds::LibrarySeeder.call!
    puts ''
    puts "Resultado: created=#{stats[:created]}, updated=#{stats[:updated]}, skipped=#{stats[:skipped]}"
  end

  desc 'Lista todos os templates Klivy globais e seus tipos.'
  task list_klivy: :environment do
    templates = DocumentTemplate.where(source: 'klivy', account_id: nil).order(:document_type, :name)
    if templates.empty?
      puts 'Nenhum template Klivy encontrado. Rode: bundle exec rake document_templates:seed_klivy_library'
    else
      puts "Templates Klivy (#{templates.count}):"
      templates.each do |t|
        puts "  [#{t.document_type.ljust(28)}] #{t.name} (v#{t.version}, status=#{t.status})"
      end
    end
  end
end
