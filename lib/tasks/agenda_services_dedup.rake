# Deduplicação de `agenda_services` por nome (case-insensitive) dentro de cada
# account. Pré-requisito para o unique index `(account_id, lower(name))` que
# vem na migration `20260513150002_add_unique_name_index_to_agenda_services.rb`.
#
# Contexto:
# Auditoria de 2026-05-13 (docs/audits/agenda-2026-05-13.md) identificou
# que `agenda_services` não tem unique constraint em `(account_id, name)`,
# permitindo duplicidade silenciosa (ex.: "Limpeza" e "limpeza" e " Limpeza ").
# Cada duplicata gera:
# - Cor visual ambígua no calendário (`getTreatmentColor` em useAgenda.js:555
#   pega o primeiro match — pode pegar a duplicata errada).
# - Filtro `hiddenTreatments` (por NAME) cobre só uma das duplicatas.
# - Plano de tratamento (TreatmentItemModal.vue) match por NAME — preço errado
#   se o operador escolheu a duplicata sem preço setado.
#
# Esta task NÃO toca:
# - `agenda_events.custom_attributes['treatment']` — string com nome do serviço
#   nos eventos antigos. Migrar isso é Fase 3 (backfill de agenda_service_id),
#   PR separado. Esta task apenas elege um sobrevivente por nome normalizado e
#   marca os perdedores como `deleted_at = NOW()`.
# - Hard delete: usa `soft_delete!` (atualiza deleted_at). Reversível por SQL
#   manual se necessário.
#
# Estratégia de sobrevivente:
# - Grupo = `(account_id, lower(strip(name)))`.
# - Vencedor = o `created_at` mais antigo do grupo (preserva o original).
# - Perdedores = todos os outros do grupo → soft-delete.
# - O nome do vencedor é normalizado (strip de espaços laterais) para fechar a
#   porta de duplicatas que diferiam só por whitespace.
#
# Uso:
#
#   1) DRY-RUN — relatório sem alterar nada:
#      bundle exec rails agenda_services:list_dupes
#
#   2) Após revisar a saída do passo 1:
#      bundle exec rails agenda_services:dedupe
#
#   3) Após dedupe rodar sem erro, executar a migration do unique index:
#      bundle exec rails db:migrate
#
# Idempotente: rodar `dedupe` 2× é seguro (segunda vez vira no-op).

namespace :agenda_services do
  desc 'DRY-RUN: lista duplicatas de agenda_services por (account_id, lower(name)) sem alterar nada'
  task list_dupes: :environment do
    puts ''
    puts '=== Agenda Services — Duplicate Report (DRY-RUN) ==='
    puts ''

    total = AgendaService.where(deleted_at: nil).count
    puts "Total de serviços ativos: #{total}"
    puts ''

    dupe_groups = AgendaService
                  .where(deleted_at: nil)
                  .group('account_id, lower(btrim(name))')
                  .having('count(*) > 1')
                  .pluck(Arel.sql('account_id, lower(btrim(name)), count(*)'))

    if dupe_groups.empty?
      puts '✓ Sem duplicatas. Base limpa, unique index pode ser aplicado.'
      next
    end

    puts "Encontrados #{dupe_groups.size} grupos com duplicatas:"
    puts ''
    puts format('%-12s | %-30s | %5s | %s', 'account_id', 'name (normalizado)', 'count', 'survivor → losers')
    puts '-' * 100

    dupe_groups.each do |account_id, name_norm, count|
      group = AgendaService.where(deleted_at: nil, account_id: account_id)
                           .where('lower(btrim(name)) = ?', name_norm)
                           .order(:created_at)
      survivor = group.first
      losers = group.offset(1).pluck(:id)

      puts format(
        '%-12s | %-30s | %5d | id=%d → kill %s',
        account_id, name_norm.to_s.first(28), count, survivor.id, losers.inspect
      )
    end

    puts ''
    puts '=== Próximo passo ==='
    puts 'Se a lista estiver OK, rode:'
    puts '  bundle exec rails agenda_services:dedupe'
    puts ''
  end

  desc 'Soft-delete agenda_services duplicados por (account_id, lower(name)). Rodar APÓS list_dupes revisado.'
  task dedupe: :environment do
    dupe_groups = AgendaService
                  .where(deleted_at: nil)
                  .group('account_id, lower(btrim(name))')
                  .having('count(*) > 1')
                  .pluck(Arel.sql('account_id, lower(btrim(name))'))

    if dupe_groups.empty?
      puts '✓ Sem duplicatas. Nada a deduplicar.'
      next
    end

    puts "Deduplicando #{dupe_groups.size} grupos..."
    puts ''

    total_killed = 0
    total_normalized = 0

    ActiveRecord::Base.transaction do
      dupe_groups.each do |account_id, name_norm|
        group = AgendaService.where(deleted_at: nil, account_id: account_id)
                             .where('lower(btrim(name)) = ?', name_norm)
                             .order(:created_at)
        survivor = group.first
        losers = group.offset(1)

        # Normaliza o nome do vencedor (strip de whitespace) — fecha a porta
        # para diferenças por espaço lateral. case-fold NÃO é aplicado: o
        # nome original (capitalização escolhida pelo operador) é preservado.
        normalized_name = survivor.name.to_s.strip
        if normalized_name != survivor.name
          survivor.update_column(:name, normalized_name)
          total_normalized += 1
        end

        losers.find_each do |loser|
          loser.update_columns(deleted_at: Time.current, updated_at: Time.current)
          total_killed += 1
        end

        puts "  account=#{account_id} '#{name_norm}': vencedor=##{survivor.id} (#{normalized_name}), " \
             "perdedores=#{losers.count}"
      end
    end

    puts ''
    puts "✓ Dedupe concluído:"
    puts "  Duplicatas soft-deletadas: #{total_killed}"
    puts "  Nomes normalizados (strip): #{total_normalized}"
    puts ''
    puts 'Próximo passo: rode a migration do unique index:'
    puts '  bundle exec rails db:migrate'
    puts ''
    puts 'Nota: os eventos antigos que referenciam o NAME do perdedor em'
    puts '`custom_attributes.treatment` continuam funcionando (a string ainda'
    puts 'casa com o NAME do vencedor, que é igual após o strip). A migração'
    puts 'definitiva (FK `agenda_events.agenda_service_id`) virá em PR posterior.'
  end
end
