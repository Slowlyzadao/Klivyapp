module Financial
  # Meta de receita (mensal/trimestral/anual). Canon §4.5.
  # Editar retroativamente recalcula gauge imediatamente.
  class RevenueGoal < ApplicationRecord
    self.table_name = 'financial_revenue_goals'

    PERIODS = %w[monthly quarterly annual].freeze

    belongs_to :account, class_name: '::Account'

    money_attribute :amount_cents, as: :amount

    validates :period, presence: true, inclusion: { in: PERIODS }
    validates :year, presence: true, numericality: { greater_than: 2000, less_than: 2100, only_integer: true }
    validates :amount_cents, numericality: { greater_than_or_equal_to: 0, only_integer: true }
    validate  :period_specific_fields

    scope :for_period, ->(period) { where(period: period) }
    scope :for_year, ->(year) { where(year: year) }

    def self.find_for(account_id:, period:, year:, month: nil, quarter: nil)
      where(account_id: account_id, period: period, year: year)
        .where(month: month, quarter: quarter)
        .first
    end

    private

    def period_specific_fields
      case period
      when 'monthly'
        errors.add(:month, 'obrigatório para meta mensal') unless (1..12).cover?(month.to_i)
      when 'quarterly'
        errors.add(:quarter, 'obrigatório para meta trimestral') unless (1..4).cover?(quarter.to_i)
      when 'annual'
        errors.add(:month, 'não permitido em meta anual') if month.present?
        errors.add(:quarter, 'não permitido em meta anual') if quarter.present?
      end
    end
  end
end
