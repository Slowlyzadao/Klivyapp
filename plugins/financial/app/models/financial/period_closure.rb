module Financial
  # Fechamento de mês contábil — bloqueia edição retroativa em Entry,
  # Installment, Expense com competence/cash_date dentro do período.
  #
  # Fluxo:
  # 1. ADMIN exporta DRE do mês via tab `Configurações > Contador`
  # 2. ADMIN aciona `Financial::Governance::ClosePeriod` — cria registro com
  #    `status='closed'`
  # 3. Models V2 com colunas de data têm validação `period_not_closed` que
  #    levanta `Financial::Errors::PeriodClosed` se tentar mexer em data
  #    dentro de período fechado
  # 4. Reabertura via `Financial::Governance::ReopenPeriod` (ADMIN only,
  #    motivo obrigatório) — `status='reopened'`, edição liberada de novo
  #
  # Sem soft-delete: registro é evento contábil (append-only conceitualmente).
  # Reabertura é update do registro original — preserva trilha (status muda
  # + reopened_at + reopened_by_id + reopen_reason populados).
  class PeriodClosure < ApplicationRecord
    self.table_name = 'financial_period_closures'

    STATUSES = %w[closed reopened].freeze

    belongs_to :account, class_name: '::Account'
    belongs_to :closed_by,   class_name: '::User', foreign_key: :closed_by_id
    belongs_to :reopened_by, class_name: '::User', foreign_key: :reopened_by_id, optional: true

    validates :period_year, presence: true,
              numericality: { greater_than_or_equal_to: 2020, less_than_or_equal_to: 2100, only_integer: true }
    validates :period_month, presence: true,
              numericality: { greater_than_or_equal_to: 1, less_than_or_equal_to: 12, only_integer: true }
    validates :closed_at, :closed_by_id, presence: true
    validates :status, presence: true, inclusion: { in: STATUSES }
    validate  :reopen_consistency

    scope :closed,   -> { where(status: 'closed') }
    scope :reopened, -> { where(status: 'reopened') }
    scope :for_period, ->(year, month) { where(period_year: year, period_month: month) }

    # Verifica se o mês `date` está fechado para uma conta.
    # Usado por validações `period_not_closed` em outros models.
    # Robusto: aceita Date, DateTime, ou String ISO (parseada).
    def self.closed_for?(account_id, date)
      return false if account_id.blank? || date.blank?

      date = date.is_a?(String) ? Date.parse(date) : date.to_date

      closed.where(
        account_id: account_id,
        period_year: date.year,
        period_month: date.month
      ).exists?
    rescue ArgumentError, NoMethodError
      false
    end

    # Range de datas que este registro cobre (1º ao último dia do mês).
    def period_range
      first = Date.new(period_year, period_month, 1)
      last = first.end_of_month
      first..last
    end

    def reopened?
      status == 'reopened'
    end

    private

    def reopen_consistency
      return unless reopened?

      errors.add(:reopened_at, 'obrigatório quando status=reopened') if reopened_at.blank?
      errors.add(:reopened_by_id, 'obrigatório quando status=reopened') if reopened_by_id.blank?
      errors.add(:reopen_reason, 'obrigatório quando status=reopened') if reopen_reason.blank?
    end
  end
end
