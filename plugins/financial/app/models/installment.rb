class Installment < ApplicationRecord
  # Soft delete
  scope :active, -> { where(deleted_at: nil) }

  # Associations
  belongs_to :account
  belongs_to :patient
  belongs_to :patient_transaction, class_name: 'Transaction', foreign_key: 'transaction_id'
  belongs_to :cash_entry, optional: true
  belongs_to :registered_by, class_name: 'User', optional: true

  # Enums
  enum :status, {
    pendente: 'pendente',
    pago: 'pago',
    vencido: 'vencido',
    cancelado: 'cancelado'
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

  # Validations
  validates :account, presence: true
  validates :patient, presence: true
  validates :patient_transaction, presence: true
  validates :number, presence: true, numericality: { greater_than: 0 }
  validates :amount, numericality: { greater_than: 0 }
  validates :due_date, presence: true

  # Scopes
  scope :by_patient, ->(patient_id) { where(patient_id: patient_id) }
  scope :paid, -> { where(status: 'pago') }
  scope :pending, -> { where(status: 'pendente') }
  scope :overdue, -> { where(status: 'vencido').or(where(status: 'pendente').where('due_date < ?', Date.today)) }

  # Methods
  def soft_delete!
    update!(deleted_at: Time.current)
  end

  def paid?
    status_pago?
  end

  def overdue?
    status_vencido? || (status_pendente? && due_date < Date.today)
  end
end
