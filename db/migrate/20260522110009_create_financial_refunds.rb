# Cria `financial_refunds` — estorno como entidade própria (não update no
# histórico). Canon Parte 6 §"Imutabilidade primeiro" + glossário "Estorno".
#
# Auditoria 2026-05-22 (`CRIT-SVC-05`): RefundPayment legacy zerava 100% da
# comissão em estorno parcial. Novo design: Refund armazena `refund_proportion_bps`
# (proporção exata em basis points) — service de estorno usa essa proporção
# pra reverter comissão proporcionalmente via CommissionEntry com
# `commission_amount_cents` negativo.
#
# Imutabilidade: Refund é append-only — TODOS os campos congelados após
# criação. Correção = novo Refund. Soft-delete só pra LGPD.
class CreateFinancialRefunds < ActiveRecord::Migration[7.1]
  def change
    create_table :financial_refunds do |t|
      t.bigint :account_id,     null: false
      t.bigint :installment_id, null: false
      # Parcela alvo do estorno (FK para financial_installments)

      t.bigint :refund_amount_cents, null: false
      # Valor a estornar (sempre > 0)

      t.integer :refund_proportion_bps, null: false
      # Proporção em basis points: 10000 = 100% da received_amount original.
      # Usado pelo service pra calcular reverso proporcional de comissão.
      # Calculado como (refund_amount / installment.received_amount * 10000).round

      t.text :reason, null: false
      # Motivo obrigatório (auditoria contábil)

      t.string :refund_method, null: false, limit: 16
      # canon: cash | pix | bank_transfer | patient_credit
      # patient_credit = não devolve dinheiro real; gera PatientCredit

      t.bigint :bank_account_id
      # Conta de origem do reembolso (null quando refund_method=patient_credit)

      t.date :refunded_at, null: false
      # Sempre data atual; nunca retroativo (canon glossário "Estorno")

      t.bigint :reverses_payment_receipt_id
      # FK opcional para PaymentReceipt original (rastreabilidade)

      t.bigint :created_by_id
      t.bigint :updated_by_id
      t.bigint :deleted_by_id
      t.datetime :deleted_at
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end

    add_index :financial_refunds, :account_id
    add_index :financial_refunds, :installment_id, where: 'deleted_at IS NULL'
    add_index :financial_refunds, %i[account_id refunded_at]
    add_index :financial_refunds, :reverses_payment_receipt_id,
              where: 'reverses_payment_receipt_id IS NOT NULL'

    add_foreign_key :financial_refunds, :accounts,
                    column: :account_id, on_delete: :restrict
    add_foreign_key :financial_refunds, :financial_installments,
                    column: :installment_id, on_delete: :restrict
    add_foreign_key :financial_refunds, :financial_bank_accounts,
                    column: :bank_account_id, on_delete: :restrict
    add_foreign_key :financial_refunds, :financial_payment_receipts,
                    column: :reverses_payment_receipt_id, on_delete: :restrict

    add_check_constraint :financial_refunds,
                         'refund_amount_cents > 0',
                         name: 'chk_refunds_amount_pos'
    add_check_constraint :financial_refunds,
                         'refund_proportion_bps BETWEEN 1 AND 10000',
                         name: 'chk_refunds_proportion_range'
    add_check_constraint :financial_refunds,
                         "refund_method IN ('cash','pix','bank_transfer','patient_credit')",
                         name: 'chk_refunds_method'
    add_check_constraint :financial_refunds,
                         "refund_method = 'patient_credit' OR bank_account_id IS NOT NULL",
                         name: 'chk_refunds_bank_required_when_real_refund'
  end
end
