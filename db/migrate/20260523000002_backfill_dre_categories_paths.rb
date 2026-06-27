# Backfill de `path` (materialized path) em `financial_dre_categories`.
#
# Bug descoberto 2026-05-23: a migration `20260522110004` rodou o WITH
# RECURSIVE antes dos seeds — quando a tabela ainda estava vazia. Os seeds
# canon criaram ~79 categorias por conta via `Financial::DreCategory.create!`,
# mas o callback `compute_path` falhava silenciosamente porque `self.id`
# ainda é nil em `before_save` (registro novo). Resultado: 79 × N accounts
# com `path = NULL` ou `path = ''`.
#
# Esta migration re-roda o WITH RECURSIVE pra TODAS as accounts agora que
# os dados existem. Também recalcula `level` por garantia.
#
# Após esta migration, o callback `after_create :assign_path_after_insert`
# (adicionado em mesmo PR) garante que novas categorias criadas via Rails
# nunca mais tenham path vazio.
class BackfillDreCategoriesPaths < ActiveRecord::Migration[7.1]
  def up
    execute <<~SQL
      WITH RECURSIVE cat_tree AS (
        SELECT id, parent_id, account_id, ARRAY[id] AS id_path, 1 AS lvl
        FROM financial_dre_categories
        WHERE parent_id IS NULL
        UNION ALL
        SELECT c.id, c.parent_id, c.account_id, ct.id_path || c.id, ct.lvl + 1
        FROM financial_dre_categories c
        INNER JOIN cat_tree ct ON c.parent_id = ct.id AND c.account_id = ct.account_id
      )
      UPDATE financial_dre_categories d
      SET path  = '/' || array_to_string(ct.id_path, '/'),
          level = ct.lvl,
          updated_at = NOW()
      FROM cat_tree ct
      WHERE d.id = ct.id
        AND (d.path IS NULL OR d.path = '' OR d.path != '/' || array_to_string(ct.id_path, '/'));
    SQL

    # Diagnóstico — quantas linhas têm path corretamente populado agora
    result = execute(<<~SQL).first
      SELECT COUNT(*)::int AS total,
             COUNT(path)::int AS with_path,
             COUNT(CASE WHEN path != '' AND path IS NOT NULL THEN 1 END)::int AS non_empty
      FROM financial_dre_categories
      WHERE deleted_at IS NULL;
    SQL
    say "Backfill resultado: total=#{result['total']}, with_path=#{result['with_path']}, non_empty=#{result['non_empty']}"
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
          'Backfill de path é idempotente — não precisa rollback. Se necessário, NULL out path manually.'
  end
end
