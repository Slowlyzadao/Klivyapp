module Financial
  # Contrato de mensalidade fixa de paciente. Gera Budget+Installment a cada
  # `frequency` (default monthly) via `Financial::GenerateRecurringBillingsJob`.
  #
  # Decisão 2026-05-28: substitui o "tipo Mensalidade" do modal Novo Lançamento
  # (que era só uma label e gerava N parcelas upfront, não recorria de fato).
  # Modelo separado pra ter motor real — pode pausar, cancelar, ter end_date
  # opcional, e o histórico fica auditável.
  class RecurringBilling < ApplicationRecord
    self.table_name = 'financial_recurring_billings'

    FREQUENCIES = %w[monthly bimonthly quarterly semiannual annual].freeze
    STATUSES    = %w[active paused completed canceled].freeze

    # Mapa frequência → meses pra somar no next_generation_at após cada geração.
    FREQUENCY_MONTHS = {
      'monthly'    => 1,
      'bimonthly'  => 2,
      'quarterly'  => 3,
      'semiannual' => 6,
      'annual'     => 12,
    }.freeze

    belongs_to :account, class_name: '::Account'
    belongs_to :patient, class_name: '::Patient'
    belongs_to :professional, class_name: '::User', optional: true
    belongs_to :payment_method, class_name: 'Financial::PaymentMethod', optional: false
    belongs_to :financial_dre_category,
               class_name: 'Financial::DreCategory',
               optional: true
    belongs_to :financial_bank_account,
               class_name: 'Financial::BankAccount',
               optional: true
    belongs_to :created_by,  class_name: '::User', optional: true
    belongs_to :paused_by,   class_name: '::User', optional: true
    belongs_to :canceled_by, class_name: '::User', optional: true

    validates :description, presence: true, length: { maximum: 200 }
    validates :amount_cents, numericality: { greater_than: 0, only_integer: true }
    validates :frequency, presence: true, inclusion: { in: FREQUENCIES }
    validates :status, presence: true, inclusion: { in: STATUSES }
    validates :start_date, presence: true
    validates :next_generation_at, presence: true
    validate  :end_after_start
    validate  :next_generation_within_range

    scope :active,    -> { where(status: 'active') }
    scope :due_today, ->(today = Date.current) { active.where('next_generation_at <= ?', today) }

    # ─── Helpers de ciclo ──────────────────────────────────────────────────
    def frequency_months
      FREQUENCY_MONTHS.fetch(frequency, 1)
    end

    def next_after(date)
      (date.to_date >> frequency_months)
    end

    def reached_end?
      end_date.present? && next_generation_at > end_date
    end

    # ─── Lifecycle helpers (lê estado, não persiste) ───────────────────────
    def active?    = status == 'active'
    def paused?    = status == 'paused'
    def completed? = status == 'completed'
    def canceled?  = status == 'canceled'
    def alive?     = deleted_at.nil?

    private

    def end_after_start
      return if end_date.blank? || start_date.blank?
      return if end_date >= start_date

      errors.add(:end_date, 'deve ser igual ou posterior à data inicial')
    end

    def next_generation_within_range
      return if next_generation_at.blank? || start_date.blank?
      return if next_generation_at >= start_date

      errors.add(:next_generation_at, 'deve ser igual ou posterior à data inicial')
    end
  end
end
