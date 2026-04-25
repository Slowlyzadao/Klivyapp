class FinancialEstimate < ApplicationRecord
  # Soft delete
  scope :active, -> { where(deleted_at: nil) }
  scope :deleted, -> { where.not(deleted_at: nil) }

  # Associations
  belongs_to :account
  belongs_to :patient
  belongs_to :treatment_plan, optional: true
  belongs_to :generated_by, class_name: 'User', optional: true
  has_many :transactions, dependent: :destroy

  # Enums
  enum :status, {
    rascunho: 'rascunho',
    enviado: 'enviado',
    aprovado: 'aprovado',
    cancelado: 'cancelado'
  }, prefix: true

  enum :discount_type, {
    percentual: 'percentual',
    fixo: 'fixo'
  }, prefix: true, _suffix: false

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
  validates :status, inclusion: { in: statuses.keys }
  validates :installments_count, numericality: { greater_than: 0 }
  validates :total, numericality: { greater_than_or_equal_to: 0 }

  # Scopes
  scope :by_patient, ->(patient_id) { where(patient_id: patient_id) }
  scope :pending, -> { where(status: %w[rascunho enviado]) }

  # Callbacks
  before_validation :calculate_total

  # Methods
  def soft_delete!
    update!(deleted_at: Time.current)
  end

  def deleted?
    deleted_at.present?
  end

  def approved?
    status_aprovado?
  end

  def calculate_total
    base = subtotal.to_f

    self.discount_amount = if discount_type == 'percentual' && discount_value.to_f > 0
                             (base * (discount_value.to_f / 100.0)).round(2)
                           elsif discount_type == 'fixo'
                             discount_value.to_f
                           else
                             0.0
                           end

    self.total = [base - discount_amount, 0.0].max
  end

  def installment_value
    return total if installments_count.to_i <= 1

    (total / installments_count).round(2)
  end

  def total_paid
    transactions.active.where(status: 'pago').sum(:amount)
  end

  def total_pending
    transactions.active.where(status: 'pendente').sum(:amount)
  end

  def total_overdue
    transactions.active.where(status: 'vencido').sum(:amount)
  end

  def generate_transactions!(actor, manual_method: nil)
    return if transactions.exists?

    base_amount = total
    installments = installments_count.to_i
    installments = 1 if installments < 1

    installment_val = (base_amount / installments).round(2)
    initial_due_date = valid_until || Date.today
    method = manual_method || payment_method

    desc_prefix = treatment_plan_id ? "Plano de Tratamento ##{treatment_plan_id}" : "Orçamento ##{id}"

    ActiveRecord::Base.transaction do
      installments.times do |i|
        number = i + 1

        amount = if number == installments
                   base_amount - (installment_val * (installments - 1))
                 else
                   installment_val
                 end

        due_date = initial_due_date + i.months

        created_tx = Transaction.create!(
          account_id: account_id,
          patient_id: patient_id,
          financial_estimate_id: id,
          registered_by_id: actor.id,
          transaction_type: 'receita',
          amount: amount.round(2),
          payment_method: method,
          status: 'pendente',
          due_date: due_date,
          installment_number: number,
          total_installments: installments,
          description: "Parcela #{number}/#{installments} — #{desc_prefix}"
        )

        next unless installments > 1

        Installment.create!(
          account_id: account_id,
          patient_id: patient_id,
          transaction_id: created_tx.id,
          number: number,
          amount: amount.round(2),
          status: 'pendente',
          due_date: due_date
        )
      end
    end
  end
end
