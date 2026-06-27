# Adiciona `lock_version` (optimistic locking do Rails) em todas as tabelas
# financeiras V2. Defesa contra "lost update" — quando duas requisições
# concorrentes editam o mesmo registro, a segunda recebe StaleObjectError.
#
# Auditoria 2026-05-22: race conditions identificadas em receive_payment,
# pay_expense, transfer_between_accounts não tinham proteção quando havia
# múltiplas abas/dispositivos do mesmo operador.
#
# Não adiciona em audit_logs / idempotency_keys (append-only) nem
# financial_period_closures (criada já com lock_version).
class AddLockVersionToFinancialV2Tables < ActiveRecord::Migration[7.1]
  TABLES = %w[
    financial_dre_categories
    financial_bank_accounts
    financial_commission_rules
    financial_recurring_expenses
    financial_revenue_goals
    financial_patient_credits
    financial_budgets
    financial_budget_items
    financial_installments
    financial_payment_receipts
    financial_payment_receipt_items
    financial_expenses
    financial_entries
    financial_commission_entries
    financial_cash_registers
    financial_cash_movements
    financial_setup_states
    financial_gateway_settings
    financial_lgpd_requests
  ].freeze

  def up
    TABLES.each do |table|
      next unless table_exists?(table)
      next if column_exists?(table, :lock_version)
      add_column table, :lock_version, :integer, null: false, default: 0
    end
  end

  def down
    TABLES.each do |table|
      next unless table_exists?(table)
      remove_column table, :lock_version if column_exists?(table, :lock_version)
    end
  end
end
