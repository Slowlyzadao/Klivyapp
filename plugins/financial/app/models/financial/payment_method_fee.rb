module Financial
  # Taxa versionada por (meio de pagamento × quantidade de parcelas × vigência).
  # Canon `mapa-financeiro.json` step 3 — "Cada parcela tem sua própria taxa".
  #
  # Imutabilidade total após criação (canon): para "alterar taxa",
  # `Service#deactivate_and_replace` inativa a antiga (status=inactive,
  # valid_to=Date.current) e cria nova com novos valores + valid_from futuro.
  # Lançamentos passados ficam vinculados à fee vigente naquele momento via
  # FK + snapshot congelado em Installment.
  class PaymentMethodFee < ApplicationRecord
    self.table_name = 'financial_payment_method_fees'

    STATUSES = %w[active inactive].freeze

    # TODOS os campos de cálculo são imutáveis (canon — snapshot histórico)
    frozen_attributes :payment_method_id, :installments_count,
                      :fee_percent_basis_points, :fee_fixed_cents,
                      :liquidation_days, :valid_from

    belongs_to :account,        class_name: '::Account'
    belongs_to :payment_method, class_name: 'Financial::PaymentMethod'

    validates :installments_count, presence: true,
              numericality: { greater_than_or_equal_to: 1, less_than_or_equal_to: 24, only_integer: true }
    validates :fee_percent_basis_points, presence: true,
              numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 10_000, only_integer: true }
    validates :fee_fixed_cents, presence: true,
              numericality: { greater_than_or_equal_to: 0, only_integer: true }
    validates :liquidation_days, presence: true,
              numericality: { greater_than_or_equal_to: 0, only_integer: true }
    validates :valid_from, presence: true
    validates :status, presence: true, inclusion: { in: STATUSES }
    validate  :valid_to_after_valid_from

    scope :active,   -> { where(status: 'active') }
    scope :inactive, -> { where(status: 'inactive') }
    scope :vigent_on, ->(date) {
      where('valid_from <= ?', date).where('valid_to IS NULL OR valid_to >= ?', date)
    }
    scope :for_installments, ->(count) { where(installments_count: count) }

    # Taxa percentual em decimal (0.0..100.0) — apenas leitura.
    def fee_percent
      return nil if fee_percent_basis_points.nil?

      BigDecimal(fee_percent_basis_points) / 100
    end

    # Calcula valor da taxa para um bruto: `pct * amount + fixed`.
    # Retorna em centavos (inteiro). Usado pelo service de recebimento.
    def calculate_fee_cents(amount_cents)
      pct = (amount_cents * fee_percent_basis_points / 10_000.0).round
      pct + fee_fixed_cents
    end

    # Modelo de repasse de MDR (F2.5 do PaymentPlanWizardV2): retorna o valor
    # que o PACIENTE deve pagar para que a CLÍNICA receba `base_cents` líquido
    # depois da operadora reter o MDR.
    #
    # Equação canônica:
    #   amount - fee(amount) = base
    #   amount - (amount * bps/10000 + fixed) = base
    #   amount * (1 - bps/10000) = base + fixed
    #   amount = (base + fixed) / (1 - bps/10000)
    #
    # Em centavos inteiros (arredondamento half-up no resultado final):
    #   amount = ROUND((base + fixed) * 10000 / (10000 - bps))
    #
    # Usado quando `PaymentMethod.passes_fee_to_patient = true`.
    # Quando `bps = 10000` (fee 100% — degenerado), retorna 0 e o caller
    # deve tratar como cenário inválido (fee não pode consumir tudo).
    def inflate_amount_cents(base_cents)
      bps = fee_percent_basis_points.to_i
      return base_cents if bps.zero? && fee_fixed_cents.to_i.zero?
      return 0 if bps >= 10_000  # fee absurda — caller decide o erro

      numerator = (base_cents.to_i + fee_fixed_cents.to_i) * 10_000
      denominator = 10_000 - bps
      (numerator.to_f / denominator).round
    end

    # Cessa a vigência (inativa) — usado pelo service de versionamento.
    # NÃO aceita mudança de valores; isso requer criar nova fee.
    def deactivate!(on_date: Date.current, user: nil)
      update!(
        status: 'inactive',
        valid_to: on_date,
        updated_by_id: user&.id
      )
    end

    private

    def valid_to_after_valid_from
      return unless valid_to.present? && valid_from.present?
      return if valid_to >= valid_from

      errors.add(:valid_to, 'deve ser maior ou igual a valid_from')
    end
  end
end
