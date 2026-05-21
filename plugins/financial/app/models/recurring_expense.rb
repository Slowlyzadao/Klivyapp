class RecurringExpense < ApplicationRecord
  belongs_to :account
  belongs_to :financial_category, optional: true
  belongs_to :bank_account, optional: true
  belongs_to :registered_by, class_name: 'User', foreign_key: :registered_by_id, optional: true
  has_many :account_transactions, foreign_key: :recurring_expense_id, dependent: :nullify

  FREQUENCIES     = %w[monthly weekly biweekly quarterly yearly].freeze
  COMPETENCE_RULES = %w[same_month previous_month].freeze
  PAYMENT_METHODS = %w[dinheiro pix cartao_credito cartao_debito boleto transferencia cheque].freeze

  validates :description, presence: true
  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :frequency, presence: true, inclusion: { in: FREQUENCIES }
  validates :due_day, presence: true, numericality: { in: 1..31 }
  validates :competence_rule, inclusion: { in: COMPETENCE_RULES }
  validates :start_date, presence: true
  validates :payment_method, inclusion: { in: PAYMENT_METHODS }, allow_nil: true
  validate :end_date_after_start_date

  scope :active, -> { where(active: true) }
  scope :pending_generation, lambda {
    active.where('last_generated_at IS NULL OR last_generated_at < ?', Date.today.beginning_of_month)
  }

  # Calcula próxima competence_date baseada na regra
  def next_competence_date(due_date)
    case competence_rule
    when 'previous_month'
      due_date.beginning_of_month - 1.month
    else # 'same_month'
      due_date.beginning_of_month
    end
  end

  # Calcula próxima due_date a partir de uma data de referência
  def next_due_date(from_date = Date.today)
    base = from_date.beginning_of_month
    candidate = safe_day(base.year, base.month, due_day)
    candidate <= from_date ? safe_day(base.next_month.year, base.next_month.month, due_day) : candidate
  end

  private

  def safe_day(year, month, day)
    Date.new(year, month, [day, Date.new(year, month, -1).day].min)
  end

  def end_date_after_start_date
    return unless start_date.present? && end_date.present?

    errors.add(:end_date, 'deve ser posterior a start_date') if end_date < start_date
  end
end
