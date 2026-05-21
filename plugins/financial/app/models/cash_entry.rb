class CashEntry < ApplicationRecord
  # Soft delete
  scope :active, -> { where(deleted_at: nil) }

  # Associations
  belongs_to :account
  belongs_to :patient, optional: true
  belongs_to :registered_by, class_name: 'User', optional: true
  belongs_to :source, polymorphic: true, optional: true  # Transaction (Bloco 4)

  # Enums
  enum :entry_type, {
    income: 'income',
    expense: 'expense',
    refund: 'refund'
  }, prefix: true

  enum :payment_method, {
    pix: 'pix',
    credit_card: 'credit_card',
    debit_card: 'debit_card',
    cash: 'cash',
    boleto: 'boleto',
    bank_transfer: 'bank_transfer',
    others: 'others'
  }, prefix: true

  # Validations
  validates :entry_type, presence: true, inclusion: { in: entry_types.keys }
  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :entry_date, presence: true
  validates :account, presence: true

  # Scopes
  scope :income, -> { where(entry_type: 'income') }
  scope :expense, -> { where(entry_type: 'expense') }
  scope :refund, -> { where(entry_type: 'refund') }
  scope :by_date_range, ->(start_date, end_date) { where(entry_date: start_date..end_date) }
  scope :by_payment_method, ->(method) { where(payment_method: method) }
  scope :ordered, -> { order(entry_date: :desc, created_at: :desc) }

  def soft_delete!
    update!(deleted_at: Time.current)
  end

  # Total de receitas no período
  def self.total_income(account_id:, start_date: nil, end_date: nil)
    scope = active.where(account_id: account_id).income
    scope = scope.by_date_range(start_date, end_date) if start_date && end_date
    scope.sum(:amount)
  end

  # Total de despesas no período
  def self.total_expense(account_id:, start_date: nil, end_date: nil)
    scope = active.where(account_id: account_id).expense
    scope = scope.by_date_range(start_date, end_date) if start_date && end_date
    scope.sum(:amount)
  end
end
