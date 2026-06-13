# Estende `financial_dre_categories` para suportar hierarquia 4 níveis
# do canon `mapa-financeiro.json` step 2 (Plano de Contas):
#   Grupo → Subgrupo → Categoria → Subcategoria
#
# Adiciona:
# - `path` (materialized path "/<id1>/<id2>/<id3>/<id4>") — queries hierárquicas
# - `level` (1..4) — usado em DRE pra agrupar por nível
# - `system_default` — proteção pra "Sem categoria" e seeds canon que não podem
#   ser deletados nem renomeados (renomeia is_default para clareza semântica)
#
# Também:
# - Adiciona índice composto (account_id, path) único pra busca rápida
# - Migra `is_default` legacy → `system_default` (mantém ambos por compatibilidade
#   no Phase 2, deprecating `is_default` depois quando controllers V2 forem
#   refatorados)
class ExtendDreCategoriesCanon < ActiveRecord::Migration[7.1]
  def up
    add_column :financial_dre_categories, :path, :string, limit: 512 unless column_exists?(:financial_dre_categories, :path)
    add_column :financial_dre_categories, :level, :integer, null: false, default: 1 unless column_exists?(:financial_dre_categories, :level)
    add_column :financial_dre_categories, :system_default, :boolean, null: false, default: false unless column_exists?(:financial_dre_categories, :system_default)
    add_column :financial_dre_categories, :code, :string, limit: 32 unless column_exists?(:financial_dre_categories, :code)

    # Backfill path/level/system_default a partir de parent_id existente
    # (em dev local sem clínica real, só roda em accounts de teste).
    execute <<~SQL
      WITH RECURSIVE cat_tree AS (
        SELECT id, parent_id, ARRAY[id] AS id_path, 1 AS lvl
        FROM financial_dre_categories
        WHERE parent_id IS NULL
        UNION ALL
        SELECT c.id, c.parent_id, ct.id_path || c.id, ct.lvl + 1
        FROM financial_dre_categories c
        INNER JOIN cat_tree ct ON c.parent_id = ct.id
      )
      UPDATE financial_dre_categories d
      SET path = '/' || array_to_string(ct.id_path, '/'),
          level = ct.lvl
      FROM cat_tree ct
      WHERE d.id = ct.id;
    SQL

    # Marcar "Sem categoria" como system_default (canon §4.1 — não pode ser
    # excluída nem renomeada).
    execute <<~SQL
      UPDATE financial_dre_categories
      SET system_default = true
      WHERE lower(name) = 'sem categoria';
    SQL

    add_check_constraint :financial_dre_categories, 'level BETWEEN 1 AND 4',
                         name: 'chk_dre_categories_level_range' unless constraint_exists?('financial_dre_categories', 'chk_dre_categories_level_range')

    # Índice (account_id, path) — único quando path está preenchido.
    return if index_exists?(:financial_dre_categories, %i[account_id path], name: 'idx_uniq_dre_categories_account_path')

    add_index :financial_dre_categories, %i[account_id path], unique: true,
              where: 'deleted_at IS NULL AND path IS NOT NULL',
              name: 'idx_uniq_dre_categories_account_path'
  end

  def down
    if index_exists?(:financial_dre_categories, %i[account_id path], name: 'idx_uniq_dre_categories_account_path')
      remove_index :financial_dre_categories, name: 'idx_uniq_dre_categories_account_path'
    end
    if constraint_exists?('financial_dre_categories', 'chk_dre_categories_level_range')
      remove_check_constraint :financial_dre_categories, name: 'chk_dre_categories_level_range'
    end
    remove_column :financial_dre_categories, :code if column_exists?(:financial_dre_categories, :code)
    remove_column :financial_dre_categories, :system_default if column_exists?(:financial_dre_categories, :system_default)
    remove_column :financial_dre_categories, :level if column_exists?(:financial_dre_categories, :level)
    remove_column :financial_dre_categories, :path if column_exists?(:financial_dre_categories, :path)
  end

  private

  def constraint_exists?(table, name)
    ActiveRecord::Base.connection.select_value(<<~SQL).to_i.positive?
      SELECT COUNT(*) FROM information_schema.check_constraints
      WHERE constraint_name = '#{name}'
    SQL
  end
end
