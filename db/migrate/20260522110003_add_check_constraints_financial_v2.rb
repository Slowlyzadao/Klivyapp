# Adiciona CHECK constraints `_cents >= 0` em colunas monetárias V2.
#
# Auditoria 2026-05-22 (`ALTO-DB-02`): nenhuma migration V2 declarou
# `add_check_constraint` em colunas `_cents`. Valor negativo pode entrar via
# SQL direto, bug de mass assignment ou erro de cálculo — quebra relatórios
# DRE silenciosamente.
#
# Colunas que aceitam negativo intencionalmente (não estão na lista):
# - financial_commission_entries.commission_amount_cents — estorno usa valor negativo
# - financial_patient_credits.amount_cents — abatimento usa negativo
# - financial_cash_registers.difference_cents — sobra/falta pode ser negativa
#
# Idempotente via verificação manual — `check_constraint_exists?` não está
# em todas as versões do Rails.
class AddCheckConstraintsFinancialV2 < ActiveRecord::Migration[7.1]
  # [table, column, constraint_name]
  CONSTRAINTS = [
    %w[financial_bank_accounts      initial_balance_cents      chk_bank_initial_balance_nonneg],
    %w[financial_recurring_expenses amount_cents               chk_recurring_amount_nonneg],
    %w[financial_revenue_goals      amount_cents               chk_revenue_goal_amount_nonneg],
    %w[financial_budgets            subtotal_cents             chk_budget_subtotal_nonneg],
    %w[financial_budgets            discount_cents             chk_budget_discount_nonneg],
    %w[financial_budgets            total_cents                chk_budget_total_nonneg],
    %w[financial_budget_items       unit_amount_cents          chk_budget_item_unit_nonneg],
    %w[financial_budget_items       total_amount_cents         chk_budget_item_total_nonneg],
    %w[financial_installments       amount_cents               chk_installment_amount_pos],
    %w[financial_installments       received_amount_cents      chk_installment_received_nonneg],
    %w[financial_payment_receipts   total_amount_cents         chk_receipt_total_pos],
    %w[financial_payment_receipt_items amount_cents            chk_receipt_item_amount_pos],
    %w[financial_expenses           amount_cents               chk_expense_amount_nonneg],
    %w[financial_expenses           paid_amount_cents          chk_expense_paid_nonneg],
    %w[financial_entries            amount_cents               chk_entry_amount_pos],
    %w[financial_commission_entries base_amount_cents          chk_commission_base_nonneg],
    %w[financial_commission_entries mdr_deduction_cents        chk_commission_mdr_nonneg],
    %w[financial_cash_registers     opening_balance_cents      chk_cash_opening_nonneg]
  ].freeze

  # Constraints que usam `_pos` (strict positive) — só onde 0 não faz sentido.
  POSITIVE_ONLY = %w[
    chk_installment_amount_pos
    chk_receipt_total_pos
    chk_receipt_item_amount_pos
    chk_entry_amount_pos
  ].freeze

  def up
    CONSTRAINTS.each do |table, column, name|
      next unless table_exists?(table) && column_exists?(table, column)
      next if constraint_exists?(table, name)

      operator = POSITIVE_ONLY.include?(name) ? '> 0' : '>= 0'
      add_check_constraint table, "#{column} #{operator}", name: name
    end
  end

  def down
    CONSTRAINTS.each do |table, _column, name|
      next unless table_exists?(table)
      next unless constraint_exists?(table, name)

      remove_check_constraint table, name: name
    end
  end

  private

  def constraint_exists?(table, name)
    ActiveRecord::Base.connection.select_value(<<~SQL).to_i.positive?
      SELECT COUNT(*) FROM information_schema.check_constraints
      WHERE constraint_name = '#{name}'
    SQL
  end
end
