module Financial
  # Despesa (A Pagar). Canon §4.7.
  # Pode ser avulsa, originada de RecurringExpense (cron mensal) ou comissão profissional.
  # Status: pendente | pago | vencido | estornado | cancelado
  class Expense < ApplicationRecord
    self.table_name = 'financial_expenses'

    STATUSES = %w[pendente pago vencido estornado cancelado].freeze
    PAYMENT_METHODS = Installment::PAYMENT_METHODS
    MODIFIER_TYPES = %w[fixed percent].freeze

    belongs_to :account, class_name: '::Account'
    belongs_to :financial_dre_category, class_name: 'Financial::DreCategory'
    belongs_to :financial_bank_account, class_name: 'Financial::BankAccount', optional: true
    belongs_to :financial_recurring_expense, class_name: 'Financial::RecurringExpense', optional: true
    belongs_to :financial_commission_entry, class_name: 'Financial::CommissionEntry', optional: true
    belongs_to :parent, class_name: 'Financial::Expense', foreign_key: :parent_expense_id, optional: true
    belongs_to :payment_method_record, class_name: 'Financial::PaymentMethod',
               foreign_key: :payment_method_id, optional: true
    has_many   :installments_children, class_name: 'Financial::Expense', foreign_key: :parent_expense_id

    belongs_to :registered_by, class_name: '::User', optional: true
    belongs_to :paid_by,       class_name: '::User', optional: true

    money_attribute :amount_cents,      as: :amount
    money_attribute :paid_amount_cents, as: :paid_amount
    money_attribute :interest_amount_cents, as: :interest_amount
    money_attribute :fine_amount_cents,     as: :fine_amount
    money_attribute :discount_amount_cents, as: :discount_amount

    validates :description, presence: true, length: { maximum: 240 }
    validates :status, presence: true, inclusion: { in: STATUSES }
    validates :payment_method, inclusion: { in: PAYMENT_METHODS }, allow_nil: true
    validates :amount_cents, numericality: { greater_than: 0, only_integer: true }
    validates :paid_amount_cents, numericality: { greater_than_or_equal_to: 0, only_integer: true }
    validates :competence_date, :due_date, presence: true
    validates :interest_type, :fine_type, :discount_type, inclusion: { in: MODIFIER_TYPES }
    validates :interest_value, :fine_value, :discount_value,
              numericality: { greater_than_or_equal_to: 0 }
    validate  :percent_values_below_100

    # Period closure: bloqueia update SOMENTE quando o usuário tenta MUDAR
    # `competence_date` pra dentro de período fechado (atalho fraudulento
    # pra inflar DRE de mês passado). Updates de status/paid_amount_cents
    # não disparam — fluxos normais de pagamento criam Entry com cash_date=hoje.
    before_update :period_not_closed, if: :competence_date_changed?

    scope :pending, -> { where(status: 'pendente') }
    scope :paid,    -> { where(status: 'pago') }
    scope :overdue, -> { where(status: 'vencido') }
    scope :open,    -> { where(status: %w[pendente vencido]) }
    scope :recurring_origin, -> { where.not(financial_recurring_expense_id: nil) }
    scope :commission_origin, -> { where.not(financial_commission_entry_id: nil) }
    scope :due_soon, ->(days = 3) {
      pending.where(due_date: Date.current..(Date.current + days.days))
    }
    scope :due_until, ->(date) { where('due_date <= ?', date) }

    def fully_paid?
      paid_amount_cents >= amount_cents
    end

    def remaining_cents
      amount_cents - paid_amount_cents
    end

    private

    def percent_values_below_100
      errors.add(:interest_value, 'percentual deve ser < 100') if interest_type == 'percent' && interest_value.to_f >= 100
      errors.add(:fine_value,     'percentual deve ser < 100') if fine_type     == 'percent' && fine_value.to_f     >= 100
      errors.add(:discount_value, 'percentual deve ser < 100') if discount_type == 'percent' && discount_value.to_f >= 100
    end
  end
end
