module Financial
  # Junction table — quanto desta parcela foi quitado neste recibo.
  # Permite recibos parciais e múltiplos recibos por parcela (em casos extremos).
  #
  # Refatorado 2026-05-22 (Fase 1B): herda de Financial::ApplicationRecord
  # pra ganhar SoftDeletable/Auditable/Stamped/MoneyAttribute + multi-tenant
  # validation. Não usava antes porque o concern de soft_delete originalmente
  # esperava `deleted_at`; agora a tabela tem (via migration de Fase 1B).
  class PaymentReceiptItem < ApplicationRecord
    self.table_name = 'financial_payment_receipt_items'

    # Imutabilidade: cada PaymentReceiptItem é uma linha do recibo; mudar
    # `amount_cents` ou `installment_id` adulteraria histórico.
    frozen_attributes :financial_payment_receipt_id,
                      :financial_installment_id,
                      :amount_cents

    belongs_to :account, class_name: '::Account'
    belongs_to :receipt, class_name: 'Financial::PaymentReceipt',
               foreign_key: :financial_payment_receipt_id
    belongs_to :installment, class_name: 'Financial::Installment',
               foreign_key: :financial_installment_id

    money_attribute :amount_cents, as: :amount

    validates :amount_cents, numericality: { greater_than: 0, only_integer: true }
  end
end
