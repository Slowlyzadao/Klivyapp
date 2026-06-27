# Adiciona Foreign Keys faltantes nas tabelas financeiras V2.
#
# Auditoria 2026-05-22 (`CRIT-DB-01`): migrations originais V2
# (`create_financial_v2_*`) declararam `bigint :account_id, null: false` etc.
# mas NÃO emitiram `add_foreign_key` — Postgres não impõe integridade
# referencial. Risco: `account_id` órfão é aceito, e em caso de bug de
# aplicação dado vaza entre tenants sem violação detectável.
#
# `on_delete: :restrict` para todas as FKs críticas — proteção contra
# deletação acidental de Account/Patient/User que ainda têm dados financeiros
# vivos. `:nullify` apenas para colunas tipicamente "stamping" (created_by_id,
# updated_by_id) cuja perda não compromete integridade financeira.
#
# Idempotente via `foreign_key_exists?` — pode rodar múltiplas vezes.
class AddMissingForeignKeysFinancialV2 < ActiveRecord::Migration[7.1]
  # [table, column, target_table, on_delete, optional]
  FKS = [
    # account_id — todas as tabelas financeiras
    %w[financial_dre_categories        account_id        accounts restrict required],
    %w[financial_bank_accounts         account_id        accounts restrict required],
    %w[financial_commission_rules      account_id        accounts restrict required],
    %w[financial_recurring_expenses    account_id        accounts restrict required],
    %w[financial_revenue_goals         account_id        accounts restrict required],
    %w[financial_patient_credits       account_id        accounts restrict required],
    %w[financial_budgets               account_id        accounts restrict required],
    %w[financial_budget_items          account_id        accounts restrict required],
    %w[financial_installments          account_id        accounts restrict required],
    %w[financial_payment_receipts      account_id        accounts restrict required],
    %w[financial_payment_receipt_items account_id        accounts restrict required],
    %w[financial_expenses              account_id        accounts restrict required],
    %w[financial_entries               account_id        accounts restrict required],
    %w[financial_commission_entries    account_id        accounts restrict required],
    %w[financial_cash_registers        account_id        accounts restrict required],
    %w[financial_cash_movements        account_id        accounts restrict required],
    %w[financial_setup_states          account_id        accounts restrict required],
    %w[financial_gateway_settings      account_id        accounts restrict required],
    %w[financial_gateway_webhook_events account_id       accounts restrict required],
    %w[financial_idempotency_keys      account_id        accounts restrict required],
    %w[financial_audit_logs            account_id        accounts restrict required],
    %w[financial_lgpd_requests         account_id        accounts restrict required],
    # patient_id
    %w[financial_patient_credits       patient_id        patients restrict required],
    %w[financial_budgets               patient_id        patients restrict optional],
    %w[financial_installments          patient_id        patients restrict optional],
    %w[financial_payment_receipts      patient_id        patients restrict optional],
    %w[financial_lgpd_requests         patient_id        patients restrict required],
    %w[financial_entries               patient_id        patients restrict optional],
    # FKs internas
    %w[financial_budget_items          financial_budget_id          financial_budgets        restrict required],
    %w[financial_installments          financial_budget_id          financial_budgets        restrict optional],
    %w[financial_payment_receipt_items financial_payment_receipt_id financial_payment_receipts restrict required],
    %w[financial_payment_receipt_items financial_installment_id     financial_installments    restrict required],
    %w[financial_commission_entries    financial_installment_id     financial_installments    restrict optional],
    %w[financial_commission_entries    financial_commission_rule_id financial_commission_rules restrict optional],
    %w[financial_commission_entries    financial_payment_receipt_id financial_payment_receipts restrict optional],
    %w[financial_commission_entries    financial_expense_id         financial_expenses         restrict optional],
    %w[financial_recurring_expenses    financial_dre_category_id    financial_dre_categories   restrict required],
    %w[financial_recurring_expenses    financial_bank_account_id    financial_bank_accounts    restrict optional],
    %w[financial_expenses              financial_dre_category_id    financial_dre_categories   restrict required],
    %w[financial_expenses              financial_bank_account_id    financial_bank_accounts    restrict required],
    %w[financial_expenses              financial_recurring_expense_id financial_recurring_expenses restrict optional],
    %w[financial_installments          financial_dre_category_id    financial_dre_categories   restrict optional],
    %w[financial_installments          replaces_installment_id      financial_installments     restrict optional],
    %w[financial_installments          renegotiated_to_id           financial_installments     restrict optional],
    %w[financial_payment_receipts      financial_bank_account_id    financial_bank_accounts    restrict required],
    %w[financial_entries               financial_bank_account_id    financial_bank_accounts    restrict required],
    %w[financial_entries               financial_dre_category_id    financial_dre_categories   restrict optional],
    %w[financial_entries               transfer_pair_id             financial_entries          restrict optional],
    %w[financial_entries               reverses_entry_id            financial_entries          restrict optional],
    %w[financial_entries               cash_register_id             financial_cash_registers   restrict optional],
    %w[financial_cash_registers        financial_bank_account_id    financial_bank_accounts    restrict required],
    %w[financial_cash_movements        financial_cash_register_id   financial_cash_registers   restrict required],
    %w[financial_cash_movements        counterpart_bank_id          financial_bank_accounts    restrict optional],
    %w[financial_dre_categories        parent_id                    financial_dre_categories   restrict optional]
  ].freeze

  def up
    FKS.each do |table, column, target, on_delete, _required|
      next unless table_exists?(table) && table_exists?(target)
      next unless column_exists?(table, column)
      next if foreign_key_exists?(table, target, column: column)

      add_foreign_key table, target, column: column, on_delete: on_delete.to_sym
    end
  end

  def down
    FKS.each do |table, column, target, _on_delete, _required|
      next unless table_exists?(table) && table_exists?(target)
      next unless foreign_key_exists?(table, target, column: column)

      remove_foreign_key table, target, column: column
    end
  end
end
