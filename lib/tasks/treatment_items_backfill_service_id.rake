# Backfill de `treatment_items.agenda_service_id` para itens de plano de
# tratamento legados que ainda linkam com `agenda_services` apenas via
# `procedure_name` (string).
#
# Contexto:
# PR #6b da auditoria 2026-05-13 (docs/audits/agenda-2026-05-13.md)
# adicionou a FK `treatment_items.agenda_service_id`. Itens criados/editados
# a partir do PR #6b são preenchidos automaticamente pelo callback
# `TreatmentItem#resolve_agenda_service_id_from_procedure_name`. Esta task
# cobre o backlog de itens antigos.
#
# Estratégia:
# - Itera itens com `agenda_service_id IS NULL` e `procedure_name` preenchido.
# - Resolve via `TreatmentItem.find_service_by_procedure_name(account_id, name)`
#   — mesmo método usado no callback do model (DRY).
# - `update_column(:agenda_service_id, ...)` — pula callbacks (não dispara
#   regeneração de PDF do plano nem audit log durante backfill em massa).
# - Idempotente: rerun é seguro; só toca rows ainda NULL.
# - Cache por (account_id, lower(name)) dentro do batch para evitar re-query.
#
# Esperado:
# - Itens cujo `procedure_name` casa com um `AgendaService.kept` no mesmo account
#   → vinculados.
# - Itens cujo procedure foi renomeado antes desta data, ou cujo serviço foi
#   soft-deletado, permanecem NULL — `procedure_name` continua sendo a
#   fonte da verdade histórica para esses casos (esperado, audit trail).
#
# Uso:
#   bundle exec rails treatment_items:list_unlinked      # DRY-RUN
#   bundle exec rails treatment_items:backfill_service_id # aplica

namespace :treatment_items do
  desc 'DRY-RUN: lista quantos treatment_items estão sem agenda_service_id mas têm procedure_name'
  task list_unlinked: :environment do
    puts ''
    puts '=== Treatment Items — Service Linkage Report (DRY-RUN) ==='
    puts ''

    total = TreatmentItem.where(deleted_at: nil).count
    with_name = TreatmentItem.where(deleted_at: nil).where.not(procedure_name: [nil, '']).count
    linked = TreatmentItem.where(deleted_at: nil).where.not(agenda_service_id: nil).count
    unlinked_with_name = TreatmentItem.where(deleted_at: nil, agenda_service_id: nil)
                                       .where.not(procedure_name: [nil, ''])
                                       .count

    puts "Total de items ativos:                            #{total}"
    puts "Com procedure_name preenchido:                    #{with_name}"
    puts "Já vinculados (agenda_service_id preenchido):     #{linked}"
    puts "Sem vínculo MAS com procedure_name (backfillable): #{unlinked_with_name}"
    puts ''

    if unlinked_with_name.zero?
      puts '✓ Nenhum item backfillable. Tudo vinculado ou sem procedure_name.'
      next
    end

    samples = TreatmentItem
              .where(deleted_at: nil, agenda_service_id: nil)
              .where.not(procedure_name: [nil, ''])
              .group(:procedure_name)
              .order(Arel.sql('count(*) DESC'))
              .limit(20)
              .count

    puts '--- Top 20 valores de `procedure_name` em items sem vínculo:'
    samples.each do |name, count|
      sample_item = TreatmentItem
                    .where(deleted_at: nil, agenda_service_id: nil, procedure_name: name)
                    .first
      svc = TreatmentItem.find_service_by_procedure_name(sample_item&.account_id, name)
      status = svc ? "→ casaria com service id=#{svc.id} (#{svc.name})" : '→ SEM match (fica NULL)'
      puts "  #{count.to_s.rjust(5)}× #{name.to_s.first(35).ljust(35)} #{status}"
    end

    puts ''
    puts '=== Próximo passo ==='
    puts 'Se a lista parece OK, rode:'
    puts '  bundle exec rails treatment_items:backfill_service_id'
    puts ''
    puts 'Items que aparecem como "SEM match" continuarão NULL — `procedure_name`'
    puts 'permanece como audit trail histórico do plano. O modal de edição vai'
    puts 'tentar resolver na hora do save via callback do model se o nome casar.'
    puts ''
  end

  desc 'Backfill: popula agenda_service_id baseado em procedure_name'
  task backfill_service_id: :environment do
    puts ''
    puts '=== Treatment Items — Backfill agenda_service_id ==='
    puts ''

    candidates = TreatmentItem.where(deleted_at: nil, agenda_service_id: nil)
                              .where.not(procedure_name: [nil, ''])

    total = candidates.count
    if total.zero?
      puts '✓ Nenhum item backfillable. Nada a fazer.'
      next
    end

    puts "Processando #{total} items em batches de 1000..."
    puts ''

    linked = 0
    skipped = 0
    processed = 0

    candidates.find_in_batches(batch_size: 1000) do |batch|
      cache = {}

      batch.each do |item|
        name = item.procedure_name.to_s.strip
        if name.blank?
          skipped += 1
          next
        end

        cache_key = [item.account_id, name.downcase]
        service = cache.fetch(cache_key) do
          cache[cache_key] = TreatmentItem.find_service_by_procedure_name(item.account_id, name)
        end

        if service
          item.update_column(:agenda_service_id, service.id)
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
    puts "  Items processados: #{processed}"
    puts "  Vinculados (NULL → ID): #{linked}"
    puts "  Sem match (permanecem NULL): #{skipped}"
    puts ''

    total_with_name = TreatmentItem.where(deleted_at: nil).where.not(procedure_name: [nil, '']).count
    total_linked = TreatmentItem.where(deleted_at: nil).where.not(agenda_service_id: nil).count
    rate = total_with_name.positive? ? (total_linked * 100.0 / total_with_name).round(2) : 0.0

    puts "Linkage rate global: #{total_linked}/#{total_with_name} = #{rate}%"
    puts ''

    if rate >= 99
      puts '✓ Linkage ≥99% — base está saudável.'
    elsif rate >= 80
      puts 'ℹ Linkage entre 80-99% — esperado se houver histórico de rename ou'
      puts '  procedimentos que não estão mais cadastrados como serviços.'
    else
      puts '⚠ Linkage abaixo de 80% — vale investigar via `list_unlinked`.'
    end
    puts ''
  end
end
