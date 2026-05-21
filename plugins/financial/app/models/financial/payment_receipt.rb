module Financial
  # Recibo agrupando 1..N parcelas pagas em um único recebimento.
  # Canon backlog Parte I §3: "Um pagamento PIX único pode quitar 3 parcelas de
  # uma vez. PaymentReceipt como entidade própria com 1..N parcelas dentro permite
  # registrar isso sem duplicar o FinancialEntry."
  class PaymentReceipt < ApplicationRecord
    self.table_name = 'financial_payment_receipts'

    PDF_STATUSES = %w[pending generated failed].freeze

    belongs_to :account, class_name: '::Account'
    belongs_to :patient, class_name: '::Patient'
    belongs_to :financial_bank_account, class_name: 'Financial::BankAccount'
    belongs_to :financial_entry, class_name: 'Financial::Entry', optional: true
    belongs_to :received_by, class_name: '::User', optional: true

    has_many :items, class_name: 'Financial::PaymentReceiptItem',
             foreign_key: :financial_payment_receipt_id, dependent: :destroy
    has_many :installments, through: :items, source: :installment

    money_attribute :gross_amount_cents,    as: :gross_amount
    money_attribute :interest_amount_cents, as: :interest_amount
    money_attribute :fine_amount_cents,     as: :fine_amount
    money_attribute :discount_amount_cents, as: :discount_amount
    money_attribute :credit_applied_cents,  as: :credit_applied
    money_attribute :net_amount_cents,      as: :net_amount

    validates :receipt_number, presence: true, uniqueness: { scope: :account_id, conditions: -> { alive } }
    validates :payment_method, presence: true, inclusion: { in: Installment::PAYMENT_METHODS }
    validates :received_at, presence: true
    validates :gross_amount_cents, :net_amount_cents, presence: true,
              numericality: { greater_than_or_equal_to: 0, only_integer: true }
    validate  :amounts_balance

    before_validation :assign_receipt_number, on: :create

    private

    def assign_receipt_number
      return if receipt_number.present?

      year = (received_at || Date.current).year
      last_seq = self.class.where(account_id: account_id)
                          .where('receipt_number LIKE ?', "REC-#{year}-%")
                          .order(receipt_number: :desc)
                          .limit(1)
                          .pluck(:receipt_number)
                          .first
      next_seq = last_seq ? last_seq.split('-').last.to_i + 1 : 1
      self.receipt_number = format('REC-%<year>d-%<seq>06d', year: year, seq: next_seq)
    end

    # net = gross + interest + fine - discount - credit_applied
    def amounts_balance
      expected = gross_amount_cents.to_i +
                 interest_amount_cents.to_i +
                 fine_amount_cents.to_i -
                 discount_amount_cents.to_i -
                 credit_applied_cents.to_i
      return if expected == net_amount_cents.to_i

      errors.add(:net_amount_cents,
                 "esperado #{expected} mas got #{net_amount_cents.to_i} " \
                 "(gross + juros + multa - desconto - crédito = net)")
    end
  end
end
