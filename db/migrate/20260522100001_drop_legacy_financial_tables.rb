# Drop total das tabelas do financeiro "Onda 1A" (legacy).
#
# Contexto (2026-05-22):
# A auditoria documentada em `docs/audits/financial-2026-05.md` apontou
# duplicação Legacy vs V2 com risco de divergência silenciosa de saldo:
# DECIMAL(10,2) impreciso, ausência de soft-delete, ausência de AuditLog,
# `dependent: :destroy` cascateando histórico.
#
# Decisão (`financial-2026-05-implementation.md` §0): drop total — sem cliente
# real em produção (a feature flag `financial_timeline_v2` foi ativada para
# TODAS as accounts em `20260507000001_enable_financial_timeline_v2_for_all_accounts`,
# e o frontend V1 já tinha sido removido em 2026-05-11, restando só redirects).
#
# Importação de dados de clínicas vindas da Clinicorp/Eddental/etc é feita
# pelo tool externo `/super_admin/migrations` consumindo a API V2 — não há
# código aqui pra migrar dados legacy → V2 porque não há dado real.
#
# Tabelas dropadas (sem ordem de FK porque V2 não depende delas):
#   - bank_accounts (DECIMAL)
#   - cash_registers + cash_register_entries (DECIMAL + dependent: :destroy)
#   - commission_rules (DECIMAL)
#   - recurring_expenses (DECIMAL)
#   - financial_categories (sem hierarquia 4 níveis)
#   - financial_estimates (DECIMAL, sem snapshot de preço)
#   - installments (legacy — V2 tem financial_installments com snapshot de taxa)
#   - account_transactions (genérica — V2 tem financial_entries especializada)
#
# Forward-only por convenção do projeto.
class DropLegacyFinancialTables < ActiveRecord::Migration[7.1]
  LEGACY_TABLES = %w[
    cash_register_entries
    cash_registers
    installments
    account_transactions
    commission_rules
    recurring_expenses
    bank_accounts
    financial_estimates
    financial_categories
  ].freeze

  def up
    LEGACY_TABLES.each do |table|
      next unless table_exists?(table)
      drop_table table, force: :cascade
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
          'Drop legacy financial — não há rollback. Restaurar via backup de DB se necessário.'
  end
end
