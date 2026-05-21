class BankAccount < ApplicationRecord
  belongs_to :account
  has_many :account_transactions, foreign_key: :bank_account_id, dependent: :nullify
  has_many :recurring_expenses, foreign_key: :bank_account_id, dependent: :nullify

  validates :name, presence: true
  validates :account_type, inclusion: { in: %w[checking savings cash] }
  validates :initial_balance, numericality: { greater_than_or_equal_to: 0 }

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:name) }

  def current_balance
    initial_balance +
      account_transactions.where(entry_type: 'entrada', status: 'recebido').sum(:amount) -
      account_transactions.where(entry_type: 'saida', status: 'pago').sum(:amount)
  end
end
