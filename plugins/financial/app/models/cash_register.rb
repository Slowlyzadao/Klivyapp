class CashRegister < ApplicationRecord
  belongs_to :account
  belongs_to :operator, class_name: 'User'
  has_many   :cash_register_entries, dependent: :destroy

  enum :status, { open: 'open', closed: 'closed' }, prefix: true

  validates :register_date,    presence: true
  validates :opening_balance,  presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :status,           presence: true

  scope :for_date, ->(date) { where(register_date: date) }
  scope :for_operator, ->(user_id) { where(operator_id: user_id) }
  scope :recent, -> { order(register_date: :desc, created_at: :desc) }

  def calculated_balance
    opening_balance + supplements - withdrawals + cash_in - cash_out
  end

  def difference
    return nil unless status_closed? && declared_balance.present?

    declared_balance - calculated_balance
  end
end
