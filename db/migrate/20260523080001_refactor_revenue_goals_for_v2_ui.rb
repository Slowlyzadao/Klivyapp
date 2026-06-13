# Refatora `financial_revenue_goals` pro canon Setup #8 (2026-05-23):
# - Era: 1 meta única por período (monthly/quarterly/annual) com 1 valor.
# - Agora: N metas custom, com 3 tiers (Mínima / Principal / Desafio),
#          datas livres, tipo (Total/Por Categoria/Por Agente), métrica
#          (valor R$ ou quantidade), status (Ativa/Encerrada).
#
# Drop dos registros legados — sem cliente real em produção (premissa Fase 1A).
# Quem usar (DashboardKpis#revenue_goal_progress) é ajustado em PR
# subsequente.
class RefactorRevenueGoalsForV2Ui < ActiveRecord::Migration[7.1]
  def up
    # 1. Limpa registros legados (sem semântica de tier)
    execute 'DELETE FROM financial_revenue_goals'

    # 2. Drop índice e colunas que não fazem sentido no canon novo
    remove_index :financial_revenue_goals, name: 'idx_uniq_revenue_goal_per_period' if index_exists_by_name?('idx_uniq_revenue_goal_per_period')
    remove_column :financial_revenue_goals, :period,  :string
    remove_column :financial_revenue_goals, :year,    :integer
    remove_column :financial_revenue_goals, :month,   :integer
    remove_column :financial_revenue_goals, :quarter, :integer

    # 3. Renomeia amount_cents legacy → target_cents (será o tier "Principal")
    rename_column :financial_revenue_goals, :amount_cents, :target_cents
    change_column_null :financial_revenue_goals, :target_cents, true

    # 4. Adiciona campos canon Setup #8
    add_column :financial_revenue_goals, :name,                       :string,  limit: 120, null: false, default: 'Meta sem nome'
    add_column :financial_revenue_goals, :kind,                       :string,  limit: 20,  null: false, default: 'total'
    add_column :financial_revenue_goals, :metric,                     :string,  limit: 20,  null: false, default: 'currency'
    add_column :financial_revenue_goals, :financial_dre_category_id,  :bigint
    add_column :financial_revenue_goals, :professional_id,            :bigint
    add_column :financial_revenue_goals, :start_date,                 :date,    null: false, default: -> { 'CURRENT_DATE' }
    add_column :financial_revenue_goals, :end_date,                   :date,    null: false, default: -> { 'CURRENT_DATE' }
    add_column :financial_revenue_goals, :min_target_cents,           :bigint
    add_column :financial_revenue_goals, :stretch_target_cents,       :bigint
    add_column :financial_revenue_goals, :min_target_qty,             :integer
    add_column :financial_revenue_goals, :target_qty,                 :integer
    add_column :financial_revenue_goals, :stretch_target_qty,         :integer
    add_column :financial_revenue_goals, :active,                     :boolean, null: false, default: true

    # 5. Indexes pra queries comuns
    add_index :financial_revenue_goals, [:account_id, :active], name: 'idx_revenue_goals_active'
    add_index :financial_revenue_goals, [:account_id, :start_date, :end_date], name: 'idx_revenue_goals_period'
    add_index :financial_revenue_goals, [:account_id, :kind], name: 'idx_revenue_goals_kind'

    # 6. Check constraints
    add_check_constraint :financial_revenue_goals,
                         "kind IN ('total', 'por_categoria', 'por_agente')",
                         name: 'chk_revenue_goals_kind'
    add_check_constraint :financial_revenue_goals,
                         "metric IN ('currency', 'count')",
                         name: 'chk_revenue_goals_metric'
    add_check_constraint :financial_revenue_goals,
                         'end_date >= start_date',
                         name: 'chk_revenue_goals_date_range'
    # Se kind=por_categoria, financial_dre_category_id obrigatório
    # Se kind=por_agente, professional_id obrigatório
    # (validamos em Rails também por causa do erro humano)
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
          'Refactor estrutural — drop manual se necessário.'
  end

  private

  def index_exists_by_name?(name)
    connection.indexes(:financial_revenue_goals).any? { |i| i.name == name }
  end
end
