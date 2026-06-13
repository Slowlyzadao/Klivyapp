module Financial
  # Comissão devida ao profissional. Status canon: provisionada → devida → paga.
  # Snapshot da regra (percent_basis_points, base) é guardado para auditoria
  # — mudança de regra futura NÃO altera comissões já calculadas.
  class CommissionEntry < ApplicationRecord
    self.table_name = 'financial_commission_entries'

    STATUSES = %w[provisionada devida paga estornada].freeze

    # Snapshot da regra congelado — auditoria 2026-05-22 (`ALTO-DB-03`).
    # `commission_rule_id` rastreia regra original; valores `base_amount_cents`,
    # `mdr_deduction_cents`, etc são o resultado real do cálculo congelado.
    # Mudar regra mais tarde NÃO altera comissões já calculadas.
    # `commission_amount_cents` NÃO é frozen: estorno proporcional cria nova
    # CommissionEntry com valor negativo via service RefundPayment.
    frozen_attributes :financial_installment_id,
                      :financial_commission_rule_id,
                      :base_amount_cents,
                      :mdr_deduction_cents,
                      :lab_deduction_cents,
                      :calc_base_cents,
                      :competence_date

    belongs_to :account, class_name: '::Account'
    belongs_to :professional, class_name: '::User'
    belongs_to :installment, class_name: 'Financial::Installment',
               foreign_key: :financial_installment_id, optional: true
    belongs_to :commission_rule, class_name: 'Financial::CommissionRule',
               foreign_key: :financial_commission_rule_id, optional: true
    belongs_to :payment_receipt, class_name: 'Financial::PaymentReceipt',
               foreign_key: :financial_payment_receipt_id, optional: true
    belongs_to :expense, class_name: 'Financial::Expense',
               foreign_key: :financial_expense_id, optional: true
    belongs_to :paid_by, class_name: '::User', optional: true

    money_attribute :base_amount_cents,        as: :base_amount
    money_attribute :mdr_deduction_cents,      as: :mdr_deduction
    money_attribute :lab_deduction_cents,      as: :lab_deduction
    money_attribute :calc_base_cents,          as: :calc_base
    money_attribute :commission_amount_cents,  as: :commission_amount

    validates :status, presence: true, inclusion: { in: STATUSES }
    validates :commission_amount_cents, presence: true,
              numericality: { greater_than_or_equal_to: 0, only_integer: true }
    validates :competence_date, presence: true

    scope :provisioned, -> { where(status: 'provisionada') }
    scope :due,         -> { where(status: 'devida') }
    scope :paid,        -> { where(status: 'paga') }
    scope :reversed,    -> { where(status: 'estornada') }
    scope :for_professional, ->(prof_id) { where(professional_id: prof_id) }
    scope :on_competence, ->(from, to) { where(competence_date: from..to) }
  end
end
