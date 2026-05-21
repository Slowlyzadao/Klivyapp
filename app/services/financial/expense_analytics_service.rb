class Financial::ExpenseAnalyticsService
  def initialize(account:)
    @account = account
    @today   = Time.zone.today
  end

  # Gráfico 13 — despesas por categoria rankeadas
  def expenses_by_category(period: nil, limit: 10)
    ref      = period.present? ? Date.parse("#{period}-01") : @today.beginning_of_month
    prev_ref = ref - 1.month

    current  = category_totals(ref)
    previous = category_totals(prev_ref)

    current.first(limit).map do |row|
      ant = previous.find { |r| r[:categoria] == row[:categoria] }&.dig(:total) || 0.0
      variacao = ant.positive? ? ((row[:total] - ant) / ant * 100).round(1) : 0.0
      row.merge(total_anterior: ant.round(2), variacao_pct: variacao)
    end
  end

  # Gráfico 14 — fixo vs variável ao longo do tempo
  def cost_structure(months: 12)
    months.downto(1).map do |n|
      ref = @today - (n - 1).months
      expenses = month_expenses(ref)
      receita  = month_revenue(ref)
      {
        mes: ref.strftime('%Y-%m'),
        fixo: expenses.fetch('fixo', 0.0).round(2),
        variavel: expenses.fetch('variavel', 0.0).round(2),
        receita: receita.round(2)
      }
    end
  end

  private

  def category_totals(ref)
    @account.account_transactions.kept
            .where(entry_type: 'saida', status: 'pago')
            .where(paid_at: ref.beginning_of_month..ref.end_of_month.end_of_day)
            .joins('LEFT JOIN financial_categories ON financial_categories.id = account_transactions.financial_category_id')
            .group('COALESCE(financial_categories.name, \'Sem categoria\')')
            .sum(:amount)
            .transform_values(&:to_f)
            .sort_by { |_, v| -v }
            .map { |nome, total| { categoria: nome, total: total.round(2) } }
  end

  def month_expenses(ref)
    @account.account_transactions.kept
            .where(entry_type: 'saida', status: 'pago')
            .where(paid_at: ref.beginning_of_month..ref.end_of_month.end_of_day)
            .joins('LEFT JOIN financial_categories ON financial_categories.id = account_transactions.financial_category_id')
            .group('COALESCE(financial_categories.cost_type, \'variavel\')')
            .sum(:amount)
            .transform_values(&:to_f)
  end

  def month_revenue(ref)
    @account.account_transactions.kept
            .where(entry_type: 'entrada', status: 'recebido')
            .where(received_at: ref.beginning_of_month..ref.end_of_month.end_of_day)
            .sum(:amount).to_f
  end
end
