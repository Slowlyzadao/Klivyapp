# Tentativa de pagamento iniciada pelo paciente via portal (PRD §9, Sprint F).
#
# Stateful: pending → awaiting_payment → paid/failed/expired/cancelled.
# Cada parcela pode ter várias tentativas; apenas uma vira `paid`. Quando isso
# acontece, `Financial::ReceivePayment` é chamado para marcar a Installment.
class PortalPayment < ApplicationRecord
  self.table_name = 'portal_payments'

  METHODS  = %w[pix boleto credit_card].freeze
  STATUSES = %w[pending awaiting_payment paid failed expired cancelled].freeze
  GATEWAYS = %w[mock asaas].freeze

  belongs_to :account
  belongs_to :patient
  belongs_to :installment, class_name: 'Financial::Installment',
             foreign_key: :financial_installment_id

  validates :method,       inclusion: { in: METHODS }
  validates :status,       inclusion: { in: STATUSES }
  validates :gateway,      inclusion: { in: GATEWAYS }
  validates :amount_cents, numericality: { greater_than: 0, only_integer: true }

  scope :open,         -> { where(status: %w[pending awaiting_payment]) }
  scope :resolved,     -> { where(status: %w[paid failed expired cancelled]) }
  scope :recent_first, -> { order(created_at: :desc) }

  def pending?           = status == 'pending'
  def awaiting_payment?  = status == 'awaiting_payment'
  def paid?              = status == 'paid'
  def expired?           = status == 'expired'
  def cancellable?       = pending? || awaiting_payment?

  def mark_awaiting!(payload: {})
    update!(status: 'awaiting_payment', gateway_payload: payload)
  end

  def mark_paid!(at: Time.current, payload: nil)
    return if paid?

    transaction do
      update!(
        status: 'paid',
        paid_at: at,
        gateway_payload: payload || gateway_payload
      )
    end
  end

  def mark_cancelled!
    return unless cancellable?

    update!(status: 'cancelled')
  end

  def mark_expired!
    return if paid?

    update!(status: 'expired')
  end
end
