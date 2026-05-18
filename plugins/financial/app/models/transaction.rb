class Transaction < ApplicationRecord
  include TimelineTrackable
  include BeclinicPurgeableAttachment

  # Soft delete
  scope :active, -> { where(deleted_at: nil) }
  scope :deleted, -> { where.not(deleted_at: nil) }

  # Associations
  belongs_to :account
  belongs_to :patient
  belongs_to :financial_estimate, optional: true
  belongs_to :registered_by, class_name: 'User', optional: true
  belongs_to :cash_entry, optional: true  # preenchido após baixa dupla
  has_many :installments, dependent: :destroy
  has_one_attached :payment_proof
  purges_attachment_with job_class: Financial::TransactionPurgeJob

  # Enums
  enum :transaction_type, {
    receita: 'receita',
    despesa: 'despesa',
    reembolso: 'reembolso'
  }, prefix: true

  enum :payment_method, {
    pix: 'pix',
    cartao_credito: 'cartao_credito',
    cartao_debito: 'cartao_debito',
    dinheiro: 'dinheiro',
    boleto: 'boleto',
    transferencia: 'transferencia',
    outros: 'outros'
  }, prefix: true

  enum :status, {
    pendente: 'pendente',
    pago: 'pago',
    vencido: 'vencido',
    cancelado: 'cancelado',
    reembolsado: 'reembolsado'
  }, prefix: true

  # Validations
  validates :account, presence: true
  validates :patient, presence: true
  validates :amount, numericality: { greater_than: 0 }
  validates :transaction_type, inclusion: { in: transaction_types.keys }
  validates :status, inclusion: { in: statuses.keys }

  # Scopes
  scope :by_patient, ->(patient_id) { where(patient_id: patient_id) }
  scope :paid, -> { where(status: 'pago') }
  scope :pending, -> { where(status: 'pendente') }
  scope :overdue, -> { where(status: 'vencido') }
  scope :income, -> { where(transaction_type: 'receita') }

  # Methods
  def soft_delete!
    update!(deleted_at: Time.current)
    schedule_attachment_purge!
  end

  def deleted?
    deleted_at.present?
  end

  def paid?
    status_pago?
  end

  def overdue?
    status_vencido? || (status_pendente? && due_date.present? && due_date < Date.today)
  end

  def parcelado?
    total_installments.to_i > 1
  end

  # ─── Callbacks de Timeline ───────────────────────────────────────────────────
  after_create_commit :record_timeline_transaction_created
  after_update_commit :record_timeline_transaction_paid, if: :saved_change_to_status?

  # ─── Sync com Financeiro Central ─────────────────────────────────────────────
  after_create_commit  :sync_to_central_on_create
  after_update_commit  :sync_to_central_on_update, if: :saved_change_to_status?

  private

  def sync_to_central_on_create
    Patients::TransactionSyncService.on_created(self)
  end

  def sync_to_central_on_update
    case status
    when 'pago'                      then Patients::TransactionSyncService.on_paid(self)
    when 'cancelado', 'reembolsado'  then Patients::TransactionSyncService.on_cancelled(self)
    end
  end

  def record_timeline_transaction_created
    amount_str = "R$ #{'%.2f' % amount}"
    evt = transaction_type_reembolso? ? 'refund' : 'payment'
    label = case transaction_type
            when 'receita' then "Cobrança registrada: #{amount_str} (#{description})"
            when 'reembolso' then "Reembolso registrado: #{amount_str}"
            else "Transação registrada: #{amount_str}"
            end

    record_timeline_event!(
      event_type: evt,
      label: label,
      actor: registered_by,
      occurred_at: Time.current,
      metadata: { valor: amount_str, tipo: transaction_type.to_s, metodo: payment_method.to_s, status: status.to_s }
    )
  end

  def record_timeline_transaction_paid
    return unless status == 'pago'

    amount_str = "R$ #{'%.2f' % amount}"
    record_timeline_event!(
      event_type: 'payment',
      label: "Pagamento confirmado: #{amount_str}",
      actor: registered_by,
      occurred_at: Time.current,
      metadata: { valor: amount_str, metodo: payment_method.to_s }
    )
  end
end
