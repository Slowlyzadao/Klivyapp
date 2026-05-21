class Financial::CommissionCalculator
  attr_reader :account, :professional, :period

  def initialize(account:, professional:, period:)
    @account      = account
    @professional = professional
    @period       = period
  end

  def call
    transactions = base_transactions
    breakdown    = transactions.filter_map { |t| calculate_for(t) }

    {
      professional: {
        id: professional.id,
        name: professional.name,
        email: professional.email
      },
      period: { start: period.first.to_s, end: period.last.to_s },
      total_commission: breakdown.sum { |b| b[:commission_amount] }.round(2),
      transaction_count: breakdown.size,
      transactions: breakdown
    }
  end

  private

  def base_transactions
    account.account_transactions
           .kept
           .entradas
           .where(professional_id: professional.id)
           .where(received_at: period)
           .where(status: 'recebido')
           .includes(:financial_category)
  end

  def calculate_for(transaction)
    rule = CommissionRule.most_specific_for(
      professional_id: professional.id,
      procedure_name: transaction.metadata&.dig('procedure_name'),
      category_id: transaction.financial_category_id
    )

    return nil unless rule

    commission = apply_rule(rule, transaction)

    {
      transaction_id: transaction.id,
      description: transaction.description,
      amount: transaction.amount.to_f,
      received_at: transaction.received_at&.to_s,
      category_name: transaction.financial_category&.name,
      rule_type: rule.commission_type,
      rule_value: rule.value.to_f,
      commission_amount: commission.round(2)
    }
  end

  def apply_rule(rule, transaction)
    case rule.commission_type
    when 'percentage_production'
      original = transaction.original_amount || transaction.amount
      original.to_f * rule.value / 100.0
    when 'percentage_received'
      transaction.amount.to_f * rule.value / 100.0
    when 'fixed_value'
      rule.value.to_f
    else
      0.0
    end
  end
end
