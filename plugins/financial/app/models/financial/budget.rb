module Financial
  # Orçamento ou plano de tratamento aprovado.
  # Canon §3 (1ª e 2ª origens): origem clínica (PT) ou avulsa (orçamento de recepção).
  # Status: rascunho | enviado | aprovado | cancelado | concluido
  class Budget < ApplicationRecord
    self.table_name = 'financial_budgets'

    STATUSES = %w[rascunho enviado aprovado cancelado concluido].freeze
    # `mensalidade_recorrente` (2026-05-28): cada cobrança gerada por um
    # Financial::RecurringBilling — Budget aprovado direto (sem rascunho),
    # 1 item + 1 Installment por período. Distinto de `mensalidade` (legado:
    # apenas label no modal Novo Lançamento, N parcelas upfront).
    ORIGINS  = %w[orcamento plano_tratamento mensalidade mensalidade_recorrente].freeze
    DISCOUNT_KINDS = %w[percentual fixo].freeze

    belongs_to :account, class_name: '::Account'
    belongs_to :patient, class_name: '::Patient'
    belongs_to :professional, class_name: '::User', optional: true
    belongs_to :treatment_plan, optional: true
    belongs_to :approved_by, class_name: '::User', optional: true
    belongs_to :canceled_by, class_name: '::User', optional: true
    # Refactor 2026-05-25: PaymentMethod específico sugerido pro orçamento.
    # Quando setado, `ApproveBudget` propaga pra cada Installment gerada
    # (a menos que custom plan defina por parcela). Opcional pra compat.
    belongs_to :payment_method_record, class_name: 'Financial::PaymentMethod',
               foreign_key: :payment_method_id, optional: true

    has_many :items, class_name: 'Financial::BudgetItem', foreign_key: :financial_budget_id, dependent: :destroy
    has_many :installments, class_name: 'Financial::Installment', foreign_key: :financial_budget_id

    money_attribute :subtotal_cents, as: :subtotal
    money_attribute :discount_cents, as: :discount
    money_attribute :total_cents,    as: :total

    validates :status, presence: true, inclusion: { in: STATUSES }
    validates :origin, presence: true, inclusion: { in: ORIGINS }
    validates :discount_kind, inclusion: { in: DISCOUNT_KINDS }, allow_nil: true
    validates :installments_count, numericality: { greater_than: 0, only_integer: true }
    validate  :total_consistency_when_approved

    scope :approved, -> { where(status: 'aprovado') }
    scope :draft,    -> { where(status: 'rascunho') }
    scope :pending_charges, -> { where(status: %w[enviado aprovado]) }

    after_create_commit :assign_patient_responsible_if_missing

    def approved?    = status == 'aprovado'
    def canceled?    = status == 'cancelado'
    def draft?       = status == 'rascunho'
    def from_clinic? = origin == 'plano_tratamento'

    # BUG-02: orçamento aprovado pode ser editado em parcelas pendentes,
    # mas não pode ser excluído se há parcela paga.
    def has_paid_installments?
      installments.where.not(status: %w[pendente vencido cancelado]).where('received_amount_cents > 0').exists?
    end

    def deletable?
      return true unless approved?
      !has_paid_installments?
    end

    def cancelable?
      !canceled? && !concluded?
    end

    def concluded?
      status == 'concluido'
    end

    private

    def total_consistency_when_approved
      return unless approved?
      return if total_cents == subtotal_cents - discount_cents

      errors.add(:total_cents, "deve ser igual a subtotal - discount (got total=#{total_cents}, expected=#{subtotal_cents - discount_cents})")
    end

    # Etapa A da auto-atribuição (decisão Mamedes 2026-05-11): primeiro orçamento
    # com profissional define o `responsible_professional_id` do paciente, se
    # ainda nulo. Casa com SessionLog/TreatmentPlan que têm o mesmo callback.
    def assign_patient_responsible_if_missing
      return if professional_id.blank?
      return unless patient
      return if patient.responsible_professional_id.present?

      patient.update_column(:responsible_professional_id, professional_id)
    end
  end
end
