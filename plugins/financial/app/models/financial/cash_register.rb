module Financial
  # Sessão diária de caixa físico. Canon §4.8.
  # Apenas 1 caixa OPEN por dia/conta. Bloqueia lançamentos em dinheiro retroativos
  # com data em sessão fechada (canon §4.8 + CT-CX-07).
  class CashRegister < ApplicationRecord
    self.table_name = 'financial_cash_registers'

    STATUSES = %w[open closed].freeze

    belongs_to :account, class_name: '::Account'
    belongs_to :financial_bank_account, class_name: 'Financial::BankAccount'
    belongs_to :operator, class_name: '::User'
    belongs_to :closed_by, class_name: '::User', optional: true
    belongs_to :reopened_by, class_name: '::User', optional: true

    has_many :cash_movements, class_name: 'Financial::CashMovement',
             foreign_key: :financial_cash_register_id, dependent: :restrict_with_error
    has_many :entries, class_name: 'Financial::Entry', foreign_key: :cash_register_id

    money_attribute :opening_balance_cents,  as: :opening_balance
    money_attribute :expected_balance_cents, as: :expected_balance
    money_attribute :counted_balance_cents,  as: :counted_balance
    money_attribute :difference_cents,       as: :difference

    validates :status, presence: true, inclusion: { in: STATUSES }
    validates :opening_balance_cents, presence: true,
              numericality: { greater_than_or_equal_to: 0, only_integer: true }
    validates :session_date, presence: true
    validate  :only_one_open_per_day, on: :create
    validate  :bank_account_must_be_cash

    scope :opened, -> { where(status: 'open') }
    scope :on_date, ->(date) { where(session_date: date) }

    def opened?
      status == 'open'
    end

    def closed?
      status == 'closed'
    end

    # Saldo esperado calculado em centavos (dinheiro físico).
    # = opening + entradas em dinheiro - saídas em dinheiro + suprimentos - sangrias.
    def calculated_expected_cents
      opening_balance_cents +
        cash_movements.where(kind: 'suprimento').sum(:amount_cents) -
        cash_movements.where(kind: 'sangria').sum(:amount_cents) +
        cash_in_total -
        cash_out_total
    end

    private

    def cash_in_total
      entries.where(direction: 'in').where(payment_method: 'dinheiro').sum(:amount_cents)
    end

    def cash_out_total
      entries.where(direction: 'out').where(payment_method: 'dinheiro').sum(:amount_cents)
    end

    def only_one_open_per_day
      return unless opened?

      conflict = self.class.where(account_id: account_id,
                                  financial_bank_account_id: financial_bank_account_id,
                                  session_date: session_date,
                                  status: 'open')
                          .where.not(id: id)
      errors.add(:base, 'já existe um caixa aberto para essa data') if conflict.exists?
    end

    def bank_account_must_be_cash
      return if financial_bank_account.blank?
      return if financial_bank_account.cash?

      errors.add(:financial_bank_account, 'deve ser do tipo cash')
    end
  end
end
