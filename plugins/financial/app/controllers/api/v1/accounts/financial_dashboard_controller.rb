class Api::V1::Accounts::FinancialDashboardController < Api::V1::Accounts::BaseController
  # GET /api/v1/accounts/:account_id/financial/dashboard
  def show
    authorize :financial_dashboard, :show?

    period  = resolve_period
    account = Current.account
    kpi     = kpis(account, period)

    render json: {
      period: { start: period.first, end: period.last },
      # KPIs (English keys used by Vue)
      income: kpi[:income],
      expense: kpi[:expense],
      new_income: kpi[:new_income],
      net_profit: kpi[:net_profit],
      income_delta: 0.0,
      expense_delta: 0.0,
      new_income_delta: 0.0,
      profit_delta: 0.0,
      receivables: receivables_summary(account),
      payables: payables_summary(account),
      delinquency: delinquency_summary(account),
      bank_accounts: bank_accounts_summary(account),
      cash_flow_mini: cash_flow_mini(account),
      monthly_sales: monthly_sales(account),
      expenses_by_category: expenses_by_category(account, period),
      revenue_by_insurance: revenue_by_insurance(account, period),
      average_ticket: average_ticket_overall(account, period)
    }
  end

  # GET /api/v1/accounts/:account_id/financial/dashboard/kpis
  def dashboard_kpis
    authorize :financial_dashboard, :show?
    render json: Financial::DashboardKpiService.new(account: Current.account).call
  end

  # GET /api/v1/accounts/:account_id/financial/dashboard/revenue_goal
  def revenue_goal
    authorize :financial_dashboard, :show?
    month = params[:month].present? ? Date.parse("#{params[:month]}-01") : Time.zone.today.beginning_of_month
    render json: Financial::RevenueGoalCalculator.new(account: Current.account, month: month).call
  end

  private

  def resolve_period
    case params[:period]
    when 'today'
      Time.zone.today..Time.zone.today
    when 'week'
      Time.zone.today.all_week
    when 'custom'
      Date.parse(params[:start_date])..Date.parse(params[:end_date])
    else
      # Frontend sends start_date/end_date without period=custom
      if params[:start_date].present? && params[:end_date].present?
        Date.parse(params[:start_date])..Date.parse(params[:end_date])
      else
        Time.zone.today.all_month
      end
    end
  end

  def base_scope(account)
    account.account_transactions.kept
  end

  def kpis(account, period)
    income = base_scope(account)
             .entradas.recebidos
             .where(received_at: period)
             .sum(:amount).to_f

    expense = base_scope(account)
              .saidas.pagos
              .where(paid_at: period)
              .sum(:amount).to_f

    new_income = base_scope(account)
                 .entradas
                 .where(created_at: period.first.beginning_of_day..period.last.end_of_day)
                 .sum(:amount).to_f

    {
      income: income,
      expense: expense,
      new_income: new_income,
      net_profit: (income - expense)
    }
  end

  def receivables_summary(account)
    scope = base_scope(account).entradas.em_aberto

    {
      overdue: scope.vencidos.sum(:amount).to_f,
      pending: scope.a_vencer.sum(:amount).to_f,
      due_today: scope.vencem_hoje.sum(:amount).to_f
    }
  end

  def payables_summary(account)
    scope = base_scope(account).saidas.em_aberto

    {
      overdue: scope.vencidos.sum(:amount).to_f,
      pending: scope.a_vencer.sum(:amount).to_f,
      due_today: scope.vencem_hoje.sum(:amount).to_f
    }
  end

  def delinquency_summary(account)
    scope = base_scope(account).entradas.em_aberto.vencidos

    {
      total: scope.sum(:amount).to_f,
      count: scope.where.not(patient_id: nil).distinct.count(:patient_id)
    }
  end

  def bank_accounts_summary(account)
    account.bank_accounts.active.ordered.map do |ba|
      {
        id: ba.id,
        name: ba.name,
        bank_name: ba.bank_name,
        account_type: ba.account_type,
        current_balance: ba.current_balance.to_f
      }
    end
  end

  def cash_flow_mini(account)
    7.downto(0).map do |days_ago|
      day      = Time.zone.today - days_ago
      entradas = base_scope(account).entradas.recebidos.where(received_at: day).sum(:amount)
      saidas   = base_scope(account).saidas.pagos.where(paid_at: day).sum(:amount)
      { date: day, entradas: entradas.to_f, saidas: saidas.to_f, saldo: (entradas - saidas).to_f }
    end
  end

  def monthly_sales(account)
    6.downto(1).map do |months_ago|
      month_start = (Time.zone.today - months_ago.months).beginning_of_month
      month_end   = month_start.end_of_month
      total = base_scope(account).entradas
                                 .where(created_at: month_start.beginning_of_day..month_end.end_of_day)
                                 .sum(:amount)
      { month: month_start.strftime('%Y-%m'), label: month_start.strftime('%b/%y'), total: total.to_f }
    end
  end

  def expenses_by_category(account, period)
    base_scope(account)
      .saidas
      .pagos
      .where(paid_at: period)
      .joins('LEFT JOIN financial_categories ON financial_categories.id = account_transactions.financial_category_id')
      .group('financial_categories.name', 'financial_categories.color')
      .select(
        'financial_categories.name AS fc_name',
        'financial_categories.color AS fc_color',
        'SUM(account_transactions.amount) AS total_amount'
      )
      .map do |row|
        {
          category_name: row.fc_name || 'Sem categoria',
          color: row.fc_color || '#64748b',
          amount: row.total_amount.to_f
        }
      end
      .sort_by { |r| -r[:amount] }
  end

  def revenue_by_insurance(account, period)
    base_scope(account)
      .entradas
      .where(status: 'recebido', received_at: period)
      .joins(<<~SQL.squish)
        LEFT JOIN financial_categories fc
          ON fc.id = account_transactions.financial_category_id
      SQL
      .group("COALESCE(account_transactions.metadata ->> 'insurance', fc.name, 'Particular')")
      .select(
        "COALESCE(account_transactions.metadata ->> 'insurance', fc.name, 'Particular') AS label",
        'COUNT(*) AS txn_count',
        'SUM(account_transactions.amount) AS total_amount'
      )
      .map do |row|
        {
          label: row.label,
          count: row.txn_count.to_i,
          amount: row.total_amount.to_f
        }
      end
      .sort_by { |r| -r[:amount] }
  end

  def average_ticket_overall(account, period)
    scope = base_scope(account).entradas.recebidos.where(received_at: period)
    count = scope.count
    total = scope.sum(:amount).to_f
    { count: count, total: total, ticket: count.positive? ? total / count : 0.0 }
  end
end
