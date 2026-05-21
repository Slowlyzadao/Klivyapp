module Financial
  # Conta bancária ou caixa físico. Canon §4.2.
  # Tipos: checking | savings | cash | card_receivable
  # Saldo NUNCA armazenado, sempre calculado.
  class BankAccount < ApplicationRecord
    self.table_name = 'financial_bank_accounts'

    KINDS = %w[checking savings cash card_receivable].freeze

    belongs_to :account, class_name: '::Account'

    has_many :entries,           class_name: 'Financial::Entry',          foreign_key: :financial_bank_account_id
    has_many :payment_receipts,  class_name: 'Financial::PaymentReceipt', foreign_key: :financial_bank_account_id
    has_many :expenses,          class_name: 'Financial::Expense',        foreign_key: :financial_bank_account_id
    has_many :recurring_expenses, class_name: 'Financial::RecurringExpense', foreign_key: :financial_bank_account_id
    has_many :cash_registers,    class_name: 'Financial::CashRegister',   foreign_key: :financial_bank_account_id

    money_attribute :initial_balance_cents, as: :initial_balance

    validates :name, presence: true, length: { maximum: 120 }
    validates :kind, presence: true, inclusion: { in: KINDS }
    validates :name, uniqueness: { scope: :account_id, conditions: -> { alive } }
    validates :card_settlement_days, numericality: { greater_than: 0, only_integer: true },
              if: :card_receivable?

    scope :active_accounts,  -> { where(active: true) }
    scope :cash,             -> { where(kind: 'cash') }
    scope :card_receivable,  -> { where(kind: 'card_receivable') }
    scope :for_dre,          -> { where(kind: %w[checking savings cash]) }

    def cash?
      kind == 'cash'
    end

    def card_receivable?
      kind == 'card_receivable'
    end

    # Saldo calculado dinamicamente. Considera apenas entries vivas.
    # Sangria/suprimento já são entries, então o saldo já reflete corretamente.
    def current_balance_cents
      sum_in  = entries.where(direction: 'in').sum(:amount_cents)
      sum_out = entries.where(direction: 'out').sum(:amount_cents)
      initial_balance_cents + sum_in - sum_out
    end

    def current_balance
      BigDecimal(current_balance_cents) / 100
    end
  end
end
