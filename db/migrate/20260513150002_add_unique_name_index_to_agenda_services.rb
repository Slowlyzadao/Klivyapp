class AddUniqueNameIndexToAgendaServices < ActiveRecord::Migration[7.0]
  # PR #1 da auditoria de 2026-05-13 (plugins/agenda/AUDITORIA_2026-05-13.md).
  #
  # Aplica unique constraint em `(account_id, lower(btrim(name)))` para
  # `agenda_services` ativos (`deleted_at IS NULL`). Fecha a porta para:
  # - Duplicidade silenciosa por diferença de caixa ("Limpeza" vs "limpeza").
  # - Duplicidade silenciosa por espaço lateral ("Limpeza" vs " Limpeza ").
  # - Race condition em criação simultânea (duas abas criando o mesmo nome).
  #
  # AUTO-DEDUP EMBUTIDO (atualização 2026-05-14):
  # A migration dedupa registros existentes ANTES de criar o índice. Isso permite
  # deploys com auto-migrate (Easypanel etc.) sem precisar rodar manualmente a
  # rake task `agenda_services:dedupe` antes. A rake task continua disponível
  # pra usos admin (auditoria, dry-run), mas não é mais pré-requisito do deploy.
  #
  # Estratégia (espelha lib/tasks/agenda_services_dedup.rake):
  # - Agrupa por (account_id, lower(btrim(name))) onde deleted_at IS NULL.
  # - Para cada grupo com count > 1: mantém o `created_at` mais antigo
  #   (sobrevivente), soft-deleta os demais (loseres) preenchendo `deleted_at`.
  # - Normaliza o nome do sobrevivente (strip de whitespace) — fecha duplicatas
  #   que diferiam só por espaço lateral.
  # - Idempotente: rerun é seguro (segunda execução vira no-op).
  #
  # WHERE deleted_at IS NULL no índice:
  # Soft-deleted records não contam para o constraint. Permite que o usuário
  # crie um "Limpeza" novo depois de soft-deletar o antigo, sem entrar em
  # conflito. Comportamento natural esperado pela UI.
  #
  # algorithm: :concurrently:
  # Evita LOCK exclusivo na tabela durante a criação do índice — importante
  # para contas grandes em produção. Requer disable_ddl_transaction!.

  disable_ddl_transaction!

  def up
    say 'Deduping agenda_services (case-insensitive + whitespace-stripped)...'
    deduped = dedupe_agenda_services!
    say "  → #{deduped} duplicata(s) soft-deletada(s)"

    add_index :agenda_services,
              'account_id, lower(btrim(name))',
              unique: true,
              where: 'deleted_at IS NULL',
              name: 'uniq_agenda_services_account_lower_btrim_name',
              algorithm: :concurrently
  end

  def down
    remove_index :agenda_services, name: 'uniq_agenda_services_account_lower_btrim_name'
  end

  private

  def dedupe_agenda_services!
    conn = ActiveRecord::Base.connection
    losers_killed = 0

    # 1) Encontra grupos com nome normalizado duplicado dentro do mesmo account_id.
    groups_sql = <<~SQL.squish
      SELECT account_id, lower(btrim(name)) AS norm_name
      FROM agenda_services
      WHERE deleted_at IS NULL
      GROUP BY account_id, lower(btrim(name))
      HAVING count(*) > 1
    SQL
    groups = conn.execute(groups_sql).to_a

    return 0 if groups.empty?

    # 2) Pra cada grupo: mantém o created_at mais antigo, soft-deleta o resto.
    groups.each do |group|
      account_id = group['account_id'].to_i
      norm_name = group['norm_name'].to_s
      quoted_norm = conn.quote(norm_name)

      ids_sql = <<~SQL.squish
        SELECT id, name FROM agenda_services
        WHERE deleted_at IS NULL
          AND account_id = #{account_id}
          AND lower(btrim(name)) = #{quoted_norm}
        ORDER BY created_at ASC, id ASC
      SQL
      rows = conn.execute(ids_sql).to_a

      survivor = rows.first
      survivor_id = survivor['id'].to_i
      survivor_name = survivor['name'].to_s
      loser_ids = rows[1..].map { |r| r['id'].to_i }

      # 2a) Normaliza o nome do sobrevivente (strip de whitespace lateral)
      if survivor_name != survivor_name.strip
        conn.execute(<<~SQL.squish)
          UPDATE agenda_services
          SET name = btrim(name), updated_at = NOW()
          WHERE id = #{survivor_id}
        SQL
      end

      # 2b) Soft-delete dos losers
      next if loser_ids.empty?

      conn.execute(<<~SQL.squish)
        UPDATE agenda_services
        SET deleted_at = NOW(), updated_at = NOW()
        WHERE id IN (#{loser_ids.join(',')})
      SQL
      losers_killed += loser_ids.size
    end

    losers_killed
  end
end
