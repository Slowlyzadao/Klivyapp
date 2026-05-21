module Financial
  # Modelo de despesa recorrente. Canon §4.4.
  # Cron diário gera Expense para os próximos 35 dias (idempotente).
  # Editar valor afeta APENAS competências futuras.
  class RecurringExpense < ApplicationRecord
    self.table_name = 'financial_recurring_expenses'

    FREQUENCIES = %w[monthly bimonthly quarterly semiannual annual].freeze
    COMPETENCE_RULES = %w[same_month previous_month].freeze
    GENERATION_HORIZON_DAYS = 35

    belongs_to :account, class_name: '::Account'
    belongs_to :financial_dre_category, class_name: 'Financial::DreCategory'
    belongs_to :financial_bank_account, class_name: 'Financial::BankAccount', optional: true
    has_many   :expenses, class_name: 'Financial::Expense', foreign_key: :financial_recurring_expense_id

    money_attribute :amount_cents, as: :amount

    validates :name, presence: true, length: { maximum: 200 }
    validates :amount_cents, numericality: { greater_than: 0, only_integer: true }
    validates :frequency, presence: true, inclusion: { in: FREQUENCIES }
    validates :competence_rule, presence: true, inclusion: { in: COMPETENCE_RULES }
    validates :due_day, numericality: { in: 1..31, only_integer: true }
    validates :start_date, presence: true
    validate  :end_after_start

    scope :active_recurring, -> { where(active: true) }

    # Dias entre cada repetição.
    def step_in_months
      case frequency
      when 'monthly'    then 1
      when 'bimonthly'  then 2
      when 'quarterly'  then 3
      when 'semiannual' then 6
      when 'annual'     then 12
      end
    end

    # Próxima data de vencimento >= from_date dentro da vigência.
    def next_due_date(from_date)
      from_date = from_date.to_date
      return nil if end_date.present? && end_date < from_date

      # Constrói candidata baseando no due_day a partir de start_date.
      candidate = first_candidate_after(from_date)
      return nil if end_date.present? && candidate > end_date

      candidate
    end

    def competence_for(due_date)
      due_date = due_date.to_date
      competence_rule == 'previous_month' ? due_date.prev_month.beginning_of_month : due_date.beginning_of_month
    end

    private

    def first_candidate_after(from_date)
      base = start_date
      return base if base >= from_date && base.day == due_day_clamped(base)

      # Avança em passos de step_in_months até encontrar candidate >= from_date
      candidate = adjusted_due(start_date)
      candidate = adjusted_due(candidate >> step_in_months) while candidate < from_date
      candidate
    end

    def adjusted_due(date)
      Date.new(date.year, date.month, due_day_clamped(date))
    end

    def due_day_clamped(date)
      [due_day, Date.civil(date.year, date.month, -1).day].min
    end

    def end_after_start
      return if end_date.blank? || start_date.blank?

      errors.add(:end_date, 'deve ser >= start_date') if end_date < start_date
    end
  end
end
