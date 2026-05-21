module Financial
  # Parcela a receber. Canon §7.1 (status), §3 (origem).
  # Status canon: pendente | recebido | vencido | estornado | cancelado | renegociado | parcial
  #
  # BUG-01 fix: suporte a baixa parcial via received_amount_cents < amount_cents
  # com criação de nova parcela (replaces_installment_id) com o saldo restante.
  class Installment < ApplicationRecord
    self.table_name = 'financial_installments'

    STATUSES = %w[pendente parcial recebido vencido estornado cancelado renegociado].freeze
    # `credito_paciente` = pagamento via saldo a favor (PatientCredit), distinto
    # do `credito` (cartão de crédito). UX 2026-05-12: quando o crédito do
    # paciente cobre 100% do valor a receber, o `payment_method` real é esse,
    # não o método que o usuário pré-selecionou no modal (PIX default).
    PAYMENT_METHODS = %w[dinheiro pix debito credito boleto transferencia cheque multiplas credito_paciente].freeze

    belongs_to :account, class_name: '::Account'
    belongs_to :budget, class_name: 'Financial::Budget', foreign_key: :financial_budget_id
    belongs_to :patient, class_name: '::Patient'
    belongs_to :professional, class_name: '::User', optional: true
    belongs_to :financial_dre_category, class_name: 'Financial::DreCategory', optional: true
    belongs_to :renegotiated_to, class_name: 'Financial::Installment', optional: true
    belongs_to :replaces, class_name: 'Financial::Installment',
               foreign_key: :replaces_installment_id, optional: true
    has_many   :payment_receipt_items,
               class_name: 'Financial::PaymentReceiptItem',
               foreign_key: :financial_installment_id
    has_many   :commission_entries,
               class_name: 'Financial::CommissionEntry',
               foreign_key: :financial_installment_id

    # Comprovante de pagamento (PDF/JPG/PNG) — Active Storage. URL signed
    # gerada em InstallmentsController#proof_url com TTL de 15 min.
    has_one_attached :payment_proof

    money_attribute :amount_cents,          as: :amount
    money_attribute :received_amount_cents, as: :received_amount

    validates :status, presence: true, inclusion: { in: STATUSES }
    validates :payment_method, inclusion: { in: PAYMENT_METHODS }, allow_nil: true
    validates :amount_cents, numericality: { greater_than: 0, only_integer: true }
    validates :received_amount_cents, numericality: { greater_than_or_equal_to: 0, only_integer: true }
    validates :number, :total_in_series, :due_date, :competence_date, presence: true

    scope :pending,    -> { where(status: 'pendente') }
    scope :overdue,    -> { where(status: 'vencido') }
    scope :paid,       -> { where(status: 'recebido') }
    scope :reversed,   -> { where(status: 'estornado') }
    scope :open,       -> { where(status: %w[pendente vencido parcial]) }
    scope :due_until,  ->(date) { where('due_date <= ?', date) }
    scope :due_after,  ->(date) { where('due_date > ?', date) }

    def remaining_cents
      amount_cents - received_amount_cents
    end

    def remaining
      BigDecimal(remaining_cents) / 100
    end

    def fully_paid?
      received_amount_cents >= amount_cents
    end

    def partially_paid?
      received_amount_cents.positive? && !fully_paid?
    end

    def overdue?
      status == 'pendente' && due_date < Date.current
    end

    # Refresh status conforme due_date e received_amount_cents.
    # Não persiste — chamado pelo scheduler de status (job diário).
    def computed_status
      return status if %w[estornado cancelado renegociado].include?(status)
      return 'recebido' if fully_paid?
      return 'parcial'  if partially_paid?
      return 'vencido'  if due_date < Date.current

      'pendente'
    end
  end
end
