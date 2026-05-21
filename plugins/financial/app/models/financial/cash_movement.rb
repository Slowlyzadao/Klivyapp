module Financial
  # Sangria, suprimento, quebra de caixa.
  # Canon §4.8 + glossário (Sangria, Suprimento, Quebra de caixa).
  # Sangria/suprimento são neutros no DRE — geram Entry com affects_dre=false.
  # Quebra é registrada no fechamento — falta vai para Outras Despesas, sobra para Outras Receitas.
  class CashMovement < ApplicationRecord
    self.table_name = 'financial_cash_movements'

    KINDS = %w[sangria suprimento quebra_falta quebra_sobra].freeze

    belongs_to :account, class_name: '::Account'
    belongs_to :cash_register, class_name: 'Financial::CashRegister',
               foreign_key: :financial_cash_register_id
    belongs_to :financial_bank_account, class_name: 'Financial::BankAccount', optional: true
    belongs_to :registered_by, class_name: '::User', optional: true

    belongs_to :entry_in,  class_name: 'Financial::Entry',
               foreign_key: :financial_entry_in_id,  optional: true
    belongs_to :entry_out, class_name: 'Financial::Entry',
               foreign_key: :financial_entry_out_id, optional: true

    money_attribute :amount_cents, as: :amount

    validates :kind, presence: true, inclusion: { in: KINDS }
    validates :amount_cents, numericality: { greater_than: 0, only_integer: true }
    validates :occurred_at, presence: true

    scope :transfers,  -> { where(kind: %w[sangria suprimento]) }
    scope :imbalances, -> { where(kind: %w[quebra_falta quebra_sobra]) }

    def transfer?
      %w[sangria suprimento].include?(kind)
    end

    def imbalance?
      %w[quebra_falta quebra_sobra].include?(kind)
    end
  end
end
