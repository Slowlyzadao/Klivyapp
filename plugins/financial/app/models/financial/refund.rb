module Financial
  # Estorno como entidade própria (não update no histórico).
  # Canon Parte 6 §"Imutabilidade primeiro" + glossário "Estorno".
  #
  # Imutabilidade total: TODOS os campos congelados após criação. Correção =
  # criar novo Refund (não editar). Soft-delete apenas pra LGPD.
  #
  # Auditoria 2026-05-22 (`CRIT-SVC-05`): estorno parcial deve reverter
  # comissão proporcionalmente. `refund_proportion_bps` armazena a proporção
  # exata (1..10000 = 0,01% a 100%); o service `RefundPayment` usa essa
  # proporção pra criar CommissionEntry reverso com valor proporcional.
  class Refund < ApplicationRecord
    self.table_name = 'financial_refunds'

    REFUND_METHODS = %w[cash pix bank_transfer patient_credit].freeze

    # TODOS imutáveis após criação
    frozen_attributes :installment_id, :refund_amount_cents,
                      :refund_proportion_bps, :reason, :refund_method,
                      :bank_account_id, :refunded_at,
                      :reverses_payment_receipt_id

    belongs_to :account, class_name: '::Account'
    belongs_to :installment, class_name: 'Financial::Installment'
    belongs_to :bank_account,
               class_name: 'Financial::BankAccount',
               foreign_key: :bank_account_id,
               optional: true
    belongs_to :reverses_payment_receipt,
               class_name: 'Financial::PaymentReceipt',
               foreign_key: :reverses_payment_receipt_id,
               optional: true

    has_many :commission_entry_reversals,
             class_name: 'Financial::CommissionEntry',
             foreign_key: :reverses_commission_entry_id

    money_attribute :refund_amount_cents, as: :refund_amount

    validates :refund_amount_cents, presence: true,
              numericality: { greater_than: 0, only_integer: true }
    validates :refund_proportion_bps, presence: true,
              numericality: { greater_than_or_equal_to: 1, less_than_or_equal_to: 10_000, only_integer: true }
    validates :reason, presence: true, length: { minimum: 5, maximum: 500 }
    validates :refund_method, presence: true, inclusion: { in: REFUND_METHODS }
    validates :refunded_at, presence: true

    validate :bank_required_unless_patient_credit
    validate :refunded_at_not_in_future

    scope :by_method, ->(method) { where(refund_method: method) }
    scope :on_date,   ->(from, to) { where(refunded_at: from..to) }
    scope :recent,    -> { order(refunded_at: :desc, id: :desc) }

    # Proporção como decimal (0.0..1.0) — leitura conveniente
    def refund_proportion
      return nil if refund_proportion_bps.nil?

      BigDecimal(refund_proportion_bps) / 10_000
    end

    # Aplica a proporção sobre um valor (em centavos) — usado pelo service
    # pra calcular reverso proporcional de comissão.
    def apply_proportion(amount_cents)
      (amount_cents * refund_proportion_bps / 10_000.0).round
    end

    def to_patient_credit?
      refund_method == 'patient_credit'
    end

    private

    def bank_required_unless_patient_credit
      return if refund_method == 'patient_credit'
      return if bank_account_id.present?

      errors.add(:bank_account_id, 'obrigatória quando devolução é em dinheiro/pix/transferência')
    end

    def refunded_at_not_in_future
      return unless refunded_at.present?
      return if refunded_at <= Date.current

      errors.add(:refunded_at, 'não pode ser no futuro')
    end
  end
end
