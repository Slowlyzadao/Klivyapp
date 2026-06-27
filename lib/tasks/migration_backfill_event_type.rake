# Backfill de `agenda_events.event_type` para eventos importados via
# `Migration::ClinicorpAgendaImporter` antes da PR de 2026-05-21.
#
# Contexto:
# Até 2026-05-21 o importer hardcodava `event_type: 'appointment'` para todo
# evento Clinicorp ([clinicorp_agenda_importer.rb:209]). A conta 21 importou
# 46.102 eventos e todos viraram Compromisso — incluindo consultas clínicas
# reais. Foram corrigidos em massa via `update_all(event_type: 'consultation')`
# manual no console de produção, o que arrumou o caso médio mas misturou
# bloqueios e reuniões como consulta.
#
# A PR de classificação introduz `Migration::ClinicorpAgendaImporter.classify_event_type`
# (a partir de `CategoryDescription` + presença de paciente). Esta rake task
# aplica o mesmo classifier aos eventos já criados, recuperando a distinção
# correta entre consulta / bloqueio / compromisso.
#
# Estratégia:
# - Filtra eventos cujo `custom_attributes->>'source' = 'clinicorp'` (escopo
#   exato dos eventos criados pelo importer).
# - Lê a categoria de cada evento via `custom_attributes['attr_<id>']`, onde
#   `<id>` é o AgendaCustomAttribute "Categoria" daquela conta. Cacheado por
#   conta pra evitar N+1.
# - Reclassifica via `classify_event_type` e aplica `update_columns` quando
#   o tipo precisa mudar — pula callbacks (não queremos disparar timeline
#   nem notificação durante backfill).
# - Idempotente: rerun é seguro; eventos já no tipo correto são pulados.
# - Multi-tenant: escopo obrigatório por `account_id` no argumento da task.
#
# Uso:
#   bundle exec rails 'migration:list_event_type_drift[21]'        # DRY-RUN
#   bundle exec rails 'migration:backfill_event_type[21]'          # aplica
#   DRY_RUN=true bundle exec rails 'migration:backfill_event_type[21]'  # alias
#
# Output: relatório de quantos eventos mudam de tipo, agrupado por
# (tipo_atual → tipo_correto), com amostra de títulos.

namespace :migration do
  desc 'DRY-RUN: lista quantos agenda_events do Clinicorp mudariam de event_type'
  task :list_event_type_drift, [:account_id] => :environment do |_t, args|
    account_id = args[:account_id].to_i
    abort 'Uso: rails "migration:list_event_type_drift[<account_id>]"' if account_id.zero?

    account = Account.find(account_id)
    report_drift(account, dry_run: true)
  end

  desc 'Aplica o classifier atual aos agenda_events do Clinicorp já criados'
  task :backfill_event_type, [:account_id] => :environment do |_t, args|
    account_id = args[:account_id].to_i
    abort 'Uso: rails "migration:backfill_event_type[<account_id>]"' if account_id.zero?

    account = Account.find(account_id)
    dry_run = ENV['DRY_RUN'] == 'true'
    report_drift(account, dry_run: dry_run)
  end

  # Helpers ────────────────────────────────────────────────────────────────────

  def report_drift(account, dry_run:)
    puts ''
    puts '=== Migration — Backfill event_type (Clinicorp) ==='
    puts "Conta: #{account.id} (#{account.name})"
    puts "Modo:  #{dry_run ? 'DRY-RUN (nenhuma alteração)' : 'APLICANDO mudanças'}"
    puts ''

    # AgendaCustomAttribute "Categoria" da conta — única fonte do
    # CategoryDescription preservado pelo importer. Pode não existir se a
    # conta nunca importou (caso em que não há eventos clinicorp também).
    category_attr = AgendaCustomAttribute.where(account_id: account.id)
                                         .where('LOWER(name) = ?', 'categoria').first
    category_key = category_attr ? "attr_#{category_attr.id}" : nil

    scope = AgendaEvent.where(account_id: account.id)
                       .where("custom_attributes->>'source' = ?", 'clinicorp')

    total = scope.count
    if total.zero?
      puts 'Nenhum evento clinicorp encontrado para essa conta — nada a fazer.'
      puts ''
      return
    end

    puts "Eventos clinicorp totais: #{total}"
    puts ''

    transitions = Hash.new(0)  # { ['appointment', 'consultation'] => 142 }
    samples     = Hash.new { |h, k| h[k] = [] } # mesma chave → até 3 títulos
    unchanged   = 0
    updated     = 0
    batch_size  = 1000

    scope.find_in_batches(batch_size: batch_size) do |batch|
      batch.each do |event|
        current = event.event_type.to_s
        category = category_key ? event.custom_attributes&.[](category_key) : nil
        target = Migration::ClinicorpAgendaImporter.classify_event_type(
          category: category,
          patient_present: event.contact_id.present?
        )

        if target == current
          unchanged += 1
          next
        end

        transitions[[current, target]] += 1
        samples[[current, target]] << event.title if samples[[current, target]].size < 3

        unless dry_run
          event.update_columns(event_type: target, updated_at: Time.current)
          updated += 1
        end
      end
    end

    puts '--- Transições de event_type ---'
    if transitions.empty?
      puts '  ✓ Nenhum drift detectado — todos os eventos já estão no tipo correto.'
    else
      transitions.sort_by { |_, c| -c }.each do |(from, to), count|
        puts "  #{count.to_s.rjust(6)}× #{from.ljust(13)} → #{to}"
        samples[[from, to]].each do |t|
          puts "         e.g. \"#{t.to_s.first(60)}\""
        end
      end
    end

    puts ''
    puts '--- Resumo ---'
    puts "  Inalterados (já corretos):    #{unchanged}"
    if dry_run
      puts "  Mudariam de tipo:             #{transitions.values.sum}"
      puts ''
      puts 'Pra aplicar:'
      puts "  bundle exec rails 'migration:backfill_event_type[#{account.id}]'"
    else
      puts "  Atualizados:                  #{updated}"
    end
    puts ''
  end
end
