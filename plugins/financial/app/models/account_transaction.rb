class AccountTransaction < ApplicationRecord
  belongs_to :account
  belongs_to :patient, optional: true
  belongs_to :financial_category, optional: true
  belongs_to :bank_account, optional: true
  belongs_to :registered_by, class_name: 'User', foreign_key: :registered_by_id, optional: true
  belongs_to :professional, class_name: 'User', foreign_key: :professional_id, optional: true
  belongs_to :source_transaction, class_name: 'Transaction', foreign_key: :source_transaction_id, optional: true
  belongs_to :recurring_expense, optional: true
  belongs_to :estorno_de, class_name: 'AccountTransaction', foreign_key: :estorno_de_id, optional: true

  has_one_attached :payment_proof

  ENTRY_TYPES   = %w[entrada saida].freeze
  STATUSES      = %w[pendente recebido pago cancelado parcial].freeze
  ORIGINS       = %w[manual orcamento procedimento recorrente].freeze
  PAYMENT_METHODS  = %w[dinheiro pix cartao_credito cartao_debito boleto transferencia cheque].freeze
  PAYMENT_SOURCES  = %w[particular convenio plano outro].freeze

  validates :entry_type, presence: true, inclusion: { in: ENTRY_TYPES }
  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :origin, inclusion: { in: ORIGINS }, allow_nil: true
  validates :payment_method, inclusion: { in: PAYMENT_METHODS }, allow_blank: true
  validates :payment_source, inclusion: { in: PAYMENT_SOURCES }, allow_blank: true

  before_validation :nullify_blank_fields

  private

  def nullify_blank_fields
    self.payment_method = nil if payment_method.blank?
    self.payment_source = nil if payment_source.blank?
    self.financial_category_id = nil if financial_category_id.blank?
  end

  # Soft delete
  scope :kept, -> { where(deleted_at: nil) }
  scope :trashed, -> { where.not(deleted_at: nil) }

  # Entry type scopes
  scope :entradas, -> { where(entry_type: 'entrada') }
  scope :saidas, -> { where(entry_type: 'saida') }

  # Status scopes
  scope :pendentes, -> { where(status: 'pendente') }
  scope :recebidos, -> { where(status: 'recebido') }
  scope :pagos, -> { where(status: 'pago') }
  scope :cancelados, -> { where(status: 'cancelado') }
  scope :em_aberto, -> { where(status: %w[pendente parcial]) }

  # Date scopes (regime de caixa)
  scope :recebidos_em, ->(period) { recebidos.where(received_at: period) }
  scope :pagos_em, ->(period) { pagos.where(paid_at: period) }

  # Date scopes (regime de competência — DRE)
  scope :competencia_em, ->(period) { where(competence_date: period) }
  scope :vencidos, -> { em_aberto.where('due_date < ?', Date.today) }
  scope :a_vencer, -> { em_aberto.where('due_date >= ?', Date.today) }
  scope :vencem_hoje, -> { em_aberto.where(due_date: Date.today) }

  # Origin scopes
  scope :from_patient, -> { where.not(source_transaction_id: nil) }
  scope :manual, -> { where(origin: 'manual') }
  scope :recorrentes, -> { where(origin: 'recorrente') }

  def entrada?
    entry_type == 'entrada'
  end

  def saida?
    entry_type == 'saida'
  end

  def recebido?
    status == 'recebido'
  end

  def pago?
    status == 'pago'
  end

  def soft_delete!
    update!(deleted_at: Time.current)
  end

  def deleted?
    deleted_at.present?
  end

  # ─── Sync reverso: central → paciente ────────────────────────────────────────
  # Quando o financeiro central marca como recebido, atualiza a Transaction
  # do paciente correspondente (source_transaction_id).
  after_update_commit :sync_back_to_patient_transaction, if: :saved_change_to_status?

  private

  def sync_back_to_patient_transaction
    return unless source_transaction_id.present?
    return unless status == 'recebido'

    tx = Transaction.active.find_by(id: source_transaction_id)
    return unless tx
    return if tx.status_pago? # já pago, não re-dispara

    tx.update_columns(
      status:         'pago',
      paid_at:        received_at || Date.today,
      payment_method: payment_method || tx.payment_method,
      updated_at:     Time.current
    )
  end
end
