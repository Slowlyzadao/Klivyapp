class CashRegisterEntry < ApplicationRecord
  belongs_to :cash_register
  belongs_to :account

  ENTRY_TYPES    = %w[supplement withdrawal note].freeze
  PAYMENT_METHODS = %w[cash card_credit card_debit pix transfer check].freeze

  validates :entry_type, presence: true, inclusion: { in: ENTRY_TYPES }
  validates :amount,     presence: true, numericality: { greater_than: 0 }

  scope :supplements,  -> { where(entry_type: 'supplement') }
  scope :withdrawals,  -> { where(entry_type: 'withdrawal') }
end
