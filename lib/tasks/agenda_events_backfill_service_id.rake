# Backfill de `agenda_events.agenda_service_id` para eventos legados que ainda
# linkam com `agenda_services` apenas via `custom_attributes['treatment']`
# (string com o NAME do serviço).
#
# Contexto:
# Auditoria de 2026-05-13 (docs/audits/agenda-2026-05-13.md) — PR #4
# adicionou a FK `agenda_events.agenda_service_id`. Eventos novos a partir
# do PR #4 são preenchidos automaticamente pelo callback
# `AgendaEvent#resolve_agenda_service_id_from_treatment`. Esta rake task
# (PR #5) cobre o backlog de eventos antigos.
#
# Estratégia:
# - Itera eventos com `agenda_service_id IS NULL` e `treatment` JSONB presente.
# - Resolve via `AgendaEvent.find_service_by_treatment_name(account_id, name)`
#   — mesmo método usado no callback do model (DRY).
# - `update_column(:agenda_service_id, ...)` — pula callbacks (não queremos
#   disparar timeline/notificação durante backfill).
# - Idempotente: rerun é seguro; só toca em rows ainda NULL.
# - Reporta linkage rate por conta + global.
#
# Esperado:
# - Eventos cujo treatment casa com um `AgendaService.kept` no mesmo account
#   → vinculados.
# - Eventos cujo treatment nunca teve serviço cadastrado, ou serviço foi
#   renomeado antes desta data, ou foi soft-deletado → permanecem NULL.
#   Não é bug — é manifestação visível de débito histórico. O frontend (PR #6)
#   faz fallback para `custom_attributes.treatment` quando FK é NULL.
#
# Uso:
#   bundle exec rails agenda_events:list_unlinked        # DRY-RUN — relatório
#   bundle exec rails agenda_events:backfill_service_id  # aplica

namespace :agenda_events do
  desc 'DRY-RUN: lista quantos agenda_events estão sem agenda_service_id mas têm treatment no JSONB'
  task list_unlinked: :environment do
    puts ''
    puts '=== Agenda Events — Service Linkage Report (DRY-RUN) ==='
    puts ''

    total_events = AgendaEvent.count
    with_treatment = AgendaEvent.where("custom_attributes->>'treatment' IS NOT NULL")
                                .where.not("custom_attributes->>'treatment' = ''")
                                .count
    linked = AgendaEvent.where.not(agenda_service_id: nil).count
    unlinked_with_treatment = AgendaEvent.where(agenda_service_id: nil)
                                          .where("custom_attributes->>'treatment' IS NOT NULL")
                                          .where.not("custom_attributes->>'treatment' = ''")
                                          .count

    puts "Total de eventos:                                #{total_events}"
    puts "Com treatment (NAME) no JSONB:                   #{with_treatment}"
    puts "Já vinculados (agenda_service_id preenchido):    #{linked}"
    puts "Sem vínculo MAS com treatment (backfillable):    #{unlinked_with_treatment}"
    puts ''

    if unlinked_with_treatment.zero?
      puts '✓ Nenhum evento backfillable. Tudo vinculado ou sem treatment.'
      next
    end

    # Amostra dos top nomes de tratamento sem vínculo
    samples = AgendaEvent
              .where(agenda_service_id: nil)
              .where("custom_attributes->>'treatment' IS NOT NULL")
              .where.not("custom_attributes->>'treatment' = ''")
              .group(Arel.sql("custom_attributes->>'treatment'"))
              .order(Arel.sql('count(*) DESC'))
              .limit(20)
              .count

    puts '--- Top 20 valores de `treatment` em eventos sem vínculo:'
    samples.each do |name, count|
      # Tenta resolver pra um serviço — mostra se daria match no backfill
      sample_event = AgendaEvent
                     .where(agenda_service_id: nil)
                     .where("custom_attributes->>'treatment' = ?", name)
                     .first
      svc = AgendaEvent.find_service_by_treatment_name(sample_event&.account_id, name)
      status = svc ? "→ casaria com service id=#{svc.id} (#{svc.name})" : '→ SEM match (fica NULL)'
      puts "  #{count.to_s.rjust(5)}× #{name.to_s.first(35).ljust(35)} #{status}"
    end

    puts ''
    puts '=== Próximo passo ==='
    puts 'Se a lista parece OK, rode:'
    puts '  bundle exec rails agenda_events:backfill_service_id'
    puts ''
    puts 'Eventos que aparecem como "SEM match" continuarão NULL após o backfill —'
    puts 'é esperado: manifestação visível de serviços renomeados/deletados antes desta data.'
    puts 'O frontend (PR #6) usa o NAME do JSONB como fallback nesses casos.'
    puts ''
  end

  desc 'Backfill: popula agenda_service_id baseado em custom_attributes[treatment]'
  task backfill_service_id: :environment do
    puts ''
    puts '=== Agenda Events — Backfill agenda_service_id ==='
    puts ''

    candidates = AgendaEvent.where(agenda_service_id: nil)
                            .where("custom_attributes->>'treatment' IS NOT NULL")
                            .where.not("custom_attributes->>'treatment' = ''")

    total = candidates.count
    if total.zero?
      puts '✓ Nenhum evento backfillable. Nada a fazer.'
      next
    end

    puts "Processando #{total} eventos em batches de 1000..."
    puts ''

    linked = 0
    skipped = 0
    processed = 0
    batch_size = 1000

    # Cache de resolução por (account_id, lower(name)) — evita re-query para o
    # mesmo nome dentro da mesma conta. Reset por batch para não estourar memória
    # em contas com muitos nomes distintos.
    candidates.find_in_batches(batch_size: batch_size) do |batch|
      cache = {}

      batch.each do |event|
        treatment_name = event.custom_attributes&.dig('treatment').to_s.strip
        if treatment_name.blank?
          skipped += 1
          next
        end

        cache_key = [event.account_id, treatment_name.downcase]
        service = cache.fetch(cache_key) do
          cache[cache_key] = AgendaEvent.find_service_by_treatment_name(event.account_id, treatment_name)
        end

        if service
          event.update_column(:agenda_service_id, service.id)
          linked += 1
        else
          skipped += 1
        end

        processed += 1
      end

      puts "  Batch processado — total até agora: #{processed}/#{total} " \
           "(vinculados=#{linked}, sem match=#{skipped})"
    end

    puts ''
    puts '=== Resultado ==='
    puts "  Eventos processados: #{processed}"
    puts "  Vinculados (NULL → ID): #{linked}"
    puts "  Sem match (permanecem NULL): #{skipped}"
    puts ''

    # Linkage rate final pra confirmar saúde
    total_with_treatment = AgendaEvent.where("custom_attributes->>'treatment' IS NOT NULL")
                                       .where.not("custom_attributes->>'treatment' = ''")
                                       .count
    total_linked = AgendaEvent.where.not(agenda_service_id: nil).count
    rate = total_with_treatment.positive? ? (total_linked * 100.0 / total_with_treatment).round(2) : 0.0

    puts "Linkage rate global: #{total_linked}/#{total_with_treatment} = #{rate}%"
    puts ''

    if rate >= 99
      puts '✓ Linkage ≥99% — base está saudável. Próximo passo: PR #6 (frontend lê FK com fallback).'
    elsif rate >= 80
      puts 'ℹ Linkage entre 80-99% — esperado se houver histórico de rename/delete.'
      puts '  Os eventos NULL continuarão funcionando via fallback ao JSONB no frontend.'
    else
      puts '⚠ Linkage abaixo de 80% — vale investigar. Roda `list_unlinked` para ver os top nomes sem match.'
    end
    puts ''
  end
end
