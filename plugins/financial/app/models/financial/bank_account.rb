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

    # Apenas 1 default_for_receivables e 1 default_for_payments por account.
    # Garantido também por partial unique index (CRIT-DB-multi). Rails-level
    # aqui dá erro humano em vez de constraint violation crua.
    validate :only_one_default_for_receivables
    validate :only_one_default_for_payments

    scope :active_accounts,  -> { where(active: true) }
    scope :cash,             -> { where(kind: 'cash') }
    scope :card_receivable,  -> { where(kind: 'card_receivable') }
    scope :for_dre,          -> { where(kind: %w[checking savings cash]) }
    scope :default_receivable, -> { where(default_for_receivables: true) }
    scope :default_payment,    -> { where(default_for_payments: true) }

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

    # Saldo estimado HOJE (caixa) — `initial + soma de entries com cash_date
    # até hoje`. Diferente de current_balance que pega TODAS as entries; aqui
    # respeitamos o cash_date pra excluir lançamentos futuros (ex: parcelas
    # com vencimento futuro que ainda nem foram pagas).
    def estimated_balance_cents(as_of: Date.current)
      relevant = entries.where(affects_cashflow: true).where('cash_date <= ?', as_of)
      sum_in  = relevant.where(direction: 'in').sum(:amount_cents)
      sum_out = relevant.where(direction: 'out').sum(:amount_cents)
      initial_balance_cents + sum_in - sum_out
    end

    private

    def only_one_default_for_receivables
      return unless default_for_receivables
      conflict = self.class.for_account(account_id).alive.default_receivable.where.not(id: id)
      return unless conflict.exists?

      errors.add(:default_for_receivables, 'já existe outra conta marcada como padrão de recebimento')
    end

    def only_one_default_for_payments
      return unless default_for_payments
      conflict = self.class.for_account(account_id).alive.default_payment.where.not(id: id)
      return unless conflict.exists?

      errors.add(:default_for_payments, 'já existe outra conta marcada como padrão de pagamento')
    end
  end
end
