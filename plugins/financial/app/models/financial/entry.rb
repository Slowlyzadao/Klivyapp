module Financial
  # Lançamento de fluxo de caixa efetivo — ledger central.
  # UM Entry por movimento real de dinheiro. Tem dual date:
  #   - competence_date → DRE (regime competência)
  #   - cash_date       → Fluxo (regime caixa)
  # Canon Parte 6 §"Regime caixa vs competência".
  class Entry < ApplicationRecord
    self.table_name = 'financial_entries'

    DIRECTIONS = %w[in out].freeze
    KINDS = %w[
      receita despesa transferencia
      sangria suprimento quebra_caixa
      estorno_receita estorno_despesa
      juros multa desconto
      manual_entry
      mdr_fee
    ].freeze

    # Entry é registro ledger imutável (canon Parte 6 §"Imutabilidade primeiro").
    # Auditoria 2026-05-22 (`ALTO-DB-03`): TODOS os campos críticos congelados
    # após criação. Correção = criar Entry reverso (estorno_*) + novo Entry,
    # nunca update no histórico.
    frozen_attributes :direction, :kind, :amount_cents,
                      :competence_date, :cash_date,
                      :financial_bank_account_id,
                      :financial_dre_category_id,
                      :affects_dre, :affects_cashflow,
                      :patient_id, :professional_id,
                      :transfer_pair_id, :reverses_entry_id,
                      :source_type, :source_id

    belongs_to :account, class_name: '::Account'
    belongs_to :financial_bank_account, class_name: 'Financial::BankAccount'
    belongs_to :financial_dre_category, class_name: 'Financial::DreCategory', optional: true
    belongs_to :patient, class_name: '::Patient', optional: true
    belongs_to :professional, class_name: '::User', optional: true
    belongs_to :registered_by, class_name: '::User', optional: true

    belongs_to :transfer_pair, class_name: 'Financial::Entry', optional: true
    belongs_to :reverses_entry, class_name: 'Financial::Entry', optional: true

    belongs_to :cash_register, class_name: 'Financial::CashRegister', optional: true

    has_many :payment_receipts, class_name: 'Financial::PaymentReceipt', foreign_key: :financial_entry_id

    # Polymórfica para origem (PaymentReceipt | Expense | CashMovement)
    belongs_to :source_record, polymorphic: true, optional: true,
               foreign_type: :source_type, foreign_key: :source_id

    money_attribute :amount_cents, as: :amount

    validates :direction, presence: true, inclusion: { in: DIRECTIONS }
    validates :kind, presence: true, inclusion: { in: KINDS }
    validates :amount_cents, numericality: { greater_than: 0, only_integer: true }
    validates :competence_date, :cash_date, :description, presence: true

    # Entry é a SINGLE SOURCE OF TRUTH do DRE — period closure protege aqui.
    # Bloqueia create OU update onde competence/cash_date estejam em período
    # fechado. Soft-delete continua permitido (não afeta DRE; só esconde da view).
    before_save :period_not_closed, unless: :soft_delete_in_progress?

    private

    def soft_delete_in_progress?
      respond_to?(:deleted_at_changed?) && deleted_at_changed? && deleted_at.present?
    end

    public

    scope :income,       -> { where(direction: 'in') }
    scope :outflow,      -> { where(direction: 'out') }
    scope :for_dre,      -> { where(affects_dre: true) }
    scope :for_cashflow, -> { where(affects_cashflow: true) }
    scope :on_cash_date, ->(from, to) { where(cash_date: from..to) }
    scope :on_competence_date, ->(from, to) { where(competence_date: from..to) }

    def transfer?
      kind == 'transferencia' || %w[sangria suprimento].include?(kind)
    end

    def reversal?
      kind.start_with?('estorno_')
    end
  end
end
