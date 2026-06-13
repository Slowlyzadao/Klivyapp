class AddExternalIdToFinancialInstallmentsAndReceipts < ActiveRecord::Migration[7.0]
  # Importador F-10 (Clinicorp → Financial::*) precisa de chave de
  # deduplicação estável em cada nível pra re-imports não duplicarem:
  #   - financial_budgets.external_id já existe desde 20260507100002.
  #   - financial_payment_receipts e financial_installments faltavam.
  #
  # Index parcial único por conta (mesmo padrão do Budget) — permite re-rodar
  # `kind=financial` sem duplicar PaymentReceipt/Installment já criados.
  def change
    add_column :financial_payment_receipts, :external_id, :string, limit: 60
    add_index  :financial_payment_receipts, [:account_id, :external_id],
               unique: true, where: 'external_id IS NOT NULL',
               name: 'idx_uniq_receipt_external_id'

    add_column :financial_installments, :external_id, :string, limit: 60
    add_index  :financial_installments, [:account_id, :external_id],
               unique: true, where: 'external_id IS NOT NULL',
               name: 'idx_uniq_installment_external_id'

    # `financial_payment_receipts` foi criado sem `metadata` jsonb (só notes).
    # Reaproveitamos pra rastrear casos especiais do import (IsPartialPayment
    # do Clinicorp, fila de revisão manual, etc.) sem poluir notes.
    add_column :financial_payment_receipts, :metadata, :jsonb, default: {}, null: false
  end
end
