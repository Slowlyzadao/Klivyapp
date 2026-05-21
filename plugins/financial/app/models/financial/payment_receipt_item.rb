module Financial
  # Junction table — quanto desta parcela foi quitado neste recibo.
  # Permite recibos parciais e múltiplos recibos por parcela (em casos extremos).
  class PaymentReceiptItem < ::ApplicationRecord
    self.table_name = 'financial_payment_receipt_items'
    self.inheritance_column = :_type_disabled

    extend Financial::Concerns::MoneyAttribute::ClassMethods

    belongs_to :account, class_name: '::Account'
    belongs_to :receipt, class_name: 'Financial::PaymentReceipt',
               foreign_key: :financial_payment_receipt_id
    belongs_to :installment, class_name: 'Financial::Installment',
               foreign_key: :financial_installment_id

    money_attribute :amount_cents, as: :amount

    validates :amount_cents, numericality: { greater_than: 0, only_integer: true }
  end
end
