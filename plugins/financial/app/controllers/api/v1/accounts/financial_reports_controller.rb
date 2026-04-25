class Api::V1::Accounts::FinancialReportsController < Api::V1::Accounts::BaseController
  # GET /api/v1/accounts/:account_id/financial/reports/cash_flow
  def cash_flow
    authorize :financial_dashboard, :show?
    period = resolve_period
    account = Current.account

    render json: {
      period: { start: period.first, end: period.last },
      daily: daily_cash_flow(account, period),
      totals: totals(account, period)
    }
  end

  # GET /api/v1/accounts/:account_id/financial/reports/monthly_summary
  def monthly_summary
    authorize :financial_dashboard, :show?
    account = Current.account
    months = (params[:months] || 6).to_i.clamp(1, 24)

    render json: {
      months: monthly_series(account, months)
    }
  end

  # GET /api/v1/accounts/:account_id/financial/reports/dre
  # Params: period (month|quarter|year|custom), start_date, end_date, date (YYYY-MM for month)
  def dre
    authorize :financial_dashboard, :show?
    account  = Current.account
    period   = resolve_dre_period
    prior    = prior_period(period)

    render json: {
      period: { start: period.first.to_s, end: period.last.to_s },
      prior_period: { start: prior.first.to_s, end: prior.last.to_s },
      current: build_dre(account, period),
      prior: build_dre(account, prior)
    }
  end

  # GET /api/v1/accounts/:account_id/financial/reports/commissions
  # Params: professional_id (required), start_date, end_date, period (month|quarter|year)
  # Supports ?format=csv for direct download
  def commissions
    authorize :financial_dashboard, :show?
    account = Current.account

    professional_id = params.require(:professional_id)
    professional    = account.users.find(professional_id)
    period          = resolve_commission_period

    result = Financial::CommissionCalculator.new(
      account: account,
      professional: professional,
      period: period
    ).call

    if params[:format] == 'csv'
      csv_data = build_commissions_csv(result, professional)
      send_data csv_data,
                filename: "comissoes_#{professional.name.parameterize}_#{period.first}.csv",
                type: 'text/csv; charset=utf-8',
                disposition: 'attachment'
    else
      render json: result
    end
  end

  # GET /api/v1/accounts/:account_id/financial/reports/insurance
  # Params: period (month|quarter|year|custom), date, start_date, end_date
  def insurance
    authorize :financial_dashboard, :show?
    account = Current.account
    period  = resolve_commission_period

    rows = insurance_rows(account, period)
    total = rows.sum { |r| r[:amount] }

    result = {
      period: { start: period.first.to_s, end: period.last.to_s },
      rows: rows,
      total: total,
      count: rows.sum { |r| r[:count] }
    }

    if params[:format] == 'csv'
      send_data build_insurance_csv(result),
                filename: "faturamento_convenio_#{period.first}.csv",
                type: 'text/csv; charset=utf-8',
                disposition: 'attachment'
    else
      render json: result
    end
  end

  # GET /api/v1/accounts/:account_id/financial/reports/average_ticket
  # Params: same period params + optional group_by=professional|month
  def average_ticket
    authorize :financial_dashboard, :show?
    account    = Current.account
    period     = resolve_commission_period
    group_by   = params.fetch(:group_by, 'professional')

    rows = group_by == 'month' ? ticket_by_month(account, period) : ticket_by_professional(account, period)
    overall = ticket_overall(account, period)

    render json: {
      period: { start: period.first.to_s, end: period.last.to_s },
      group_by: group_by,
      rows: rows,
      overall: overall
    }
  end

  # GET /api/v1/accounts/:account_id/financial/reports/cash_flow_chart
  # Params: start_date, end_date, bank_account_id
  def cash_flow_chart
    authorize :financial_dashboard, :show?
    start_date = params[:start_date].present? ? Date.parse(params[:start_date]) : Time.zone.today.beginning_of_month
    end_date   = params[:end_date].present?   ? Date.parse(params[:end_date])   : Time.zone.today.end_of_month

    data = Financial::CashFlowCalculator.new(
      account: Current.account,
      start_date: start_date,
      end_date: end_date,
      bank_account_id: params[:bank_account_id]
    ).call

    render json: { days: data }
  end

  # ── Onda 2 ────────────────────────────────────────────────────────

  # GET financial/reports/cash_flow_projection?horizon=30&bank_account_id=
  def cash_flow_projection
    authorize :financial_dashboard, :show?
    data = Financial::CashFlowProjectionService.new(
      account: Current.account,
      horizon: (params[:horizon] || 30).to_i,
      bank_account_id: params[:bank_account_id]
    ).call
    render json: data
  end

  # GET financial/reports/receivables_forecast?month=2026-04
  def receivables_forecast
    authorize :financial_dashboard, :show?
    data = Financial::ReceivablesForecastService.new(
      account: Current.account,
      month: params[:month]
    ).call
    render json: data
  end

  # GET financial/reports/delinquency_aging
  def delinquency_aging
    authorize :financial_dashboard, :show?
    calc = Financial::DelinquencyCalculator.new(account: Current.account)
    render json: calc.aging
  end

  # GET financial/reports/delinquency_trend?months=12
  def delinquency_trend
    authorize :financial_dashboard, :show?
    calc = Financial::DelinquencyCalculator.new(account: Current.account)
    render json: calc.trend(months: (params[:months] || 12).to_i)
  end

  # GET financial/reports/delinquency_by_professional?period=2026-03
  def delinquency_by_professional
    authorize :financial_dashboard, :show?
    calc = Financial::DelinquencyCalculator.new(account: Current.account)
    render json: calc.by_professional(period: params[:period])
  end

  # ── Onda 3 ────────────────────────────────────────────────────────────

  # GET financial/reports/dre_waterfall?period=2026-03&regime=caixa
  def dre_waterfall
    authorize :financial_dashboard, :show?
    period = params[:period] || Time.zone.today.strftime('%Y-%m')
    render json: Financial::DreCalculator.new(
      account: Current.account,
      period: period,
      regime: params[:regime] || 'caixa'
    ).call
  end

  # GET financial/reports/ticket_trend?months=12
  def ticket_trend
    authorize :financial_dashboard, :show?
    svc = Financial::RevenueAnalyticsService.new(account: Current.account)
    render json: svc.average_ticket(
      months: (params[:months] || 12).to_i,
      professional_id: params[:professional_id]
    )
  end

  # GET financial/reports/revenue_by_professional?period=2026-03
  def revenue_by_professional
    authorize :financial_dashboard, :show?
    render json: Financial::ProfessionalRevenueService.new(
      account: Current.account,
      period: params[:period]
    ).call
  end

  # GET financial/reports/revenue_composition?months=6
  def revenue_composition
    authorize :financial_dashboard, :show?
    svc = Financial::RevenueAnalyticsService.new(account: Current.account)
    render json: svc.revenue_composition(months: (params[:months] || 6).to_i)
  end

  # GET financial/reports/expenses_by_category?period=2026-03&limit=10
  def expenses_by_category
    authorize :financial_dashboard, :show?
    svc = Financial::ExpenseAnalyticsService.new(account: Current.account)
    render json: svc.expenses_by_category(
      period: params[:period],
      limit: (params[:limit] || 10).to_i
    )
  end

  # GET financial/reports/cost_structure?months=12
  def cost_structure
    authorize :financial_dashboard, :show?
    svc = Financial::ExpenseAnalyticsService.new(account: Current.account)
    render json: svc.cost_structure(months: (params[:months] || 12).to_i)
  end

  # GET financial/reports/conversion_funnel?months=3
  def conversion_funnel
    authorize :financial_dashboard, :show?
    render json: Financial::ConversionAnalyticsService.new(
      account: Current.account,
      months: params[:months] || 3
    ).call
  end

  # GET financial/reports/agenda_heatmap?weeks=12
  def agenda_heatmap
    authorize :financial_dashboard, :show?
    render json: Financial::AgendaAnalyticsService.new(
      account: Current.account,
      weeks: params[:weeks] || 12
    ).call
  end

  # GET financial/reports/patient_retention?months=12
  def patient_retention
    authorize :financial_dashboard, :show?
    render json: Financial::PatientRetentionService.new(
      account: Current.account,
      months: params[:months] || 12
    ).call
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
    else # 'month'
      Time.zone.today.all_month
    end
  end

  def resolve_commission_period
    case params[:period]
    when 'quarter'
      anchor = params[:date].present? ? Date.parse("#{params[:date]}-01") : Time.zone.today
      anchor.all_quarter
    when 'year'
      anchor = params[:date].present? ? Date.parse("#{params[:date]}-01-01") : Time.zone.today
      anchor.all_year
    when 'custom'
      Date.parse(params[:start_date])..Date.parse(params[:end_date])
    else # 'month'
      anchor = params[:date].present? ? Date.parse("#{params[:date]}-01") : Time.zone.today
      anchor.all_month
    end
  end

  def base_scope(account)
    account.account_transactions.kept
  end

  def daily_cash_flow(account, period)
    period.map do |day|
      entradas = base_scope(account).entradas.recebidos.where(received_at: day).sum(:amount).to_f
      saidas   = base_scope(account).saidas.pagos.where(paid_at: day).sum(:amount).to_f
      {
        date: day.to_s,
        label: I18n.l(day, format: '%d/%m'),
        entradas: entradas,
        saidas: saidas,
        saldo: entradas - saidas
      }
    end
  end

  def totals(account, period)
    entradas = base_scope(account).entradas.recebidos.where(received_at: period).sum(:amount).to_f
    saidas   = base_scope(account).saidas.pagos.where(paid_at: period).sum(:amount).to_f
    {
      entradas: entradas,
      saidas: saidas,
      saldo: entradas - saidas,
      saldo_inicial: opening_balance(account, period.first)
    }
  end

  def opening_balance(account, date)
    # Saldo acumulado até o dia anterior ao período
    day_before = date - 1
    ent = base_scope(account).entradas.recebidos.where(received_at: ..day_before).sum(:amount).to_f
    sai = base_scope(account).saidas.pagos.where(paid_at: ..day_before).sum(:amount).to_f
    initial = account.bank_accounts.active.sum(:initial_balance).to_f
    initial + ent - sai
  end

  def monthly_series(account, months)
    months.downto(1).map do |offset|
      start  = (Time.zone.today - offset.months).beginning_of_month
      finish = start.end_of_month
      ent = base_scope(account).entradas.recebidos.where(received_at: start..finish).sum(:amount).to_f
      sai = base_scope(account).saidas.pagos.where(paid_at: start..finish).sum(:amount).to_f
      {
        month: start.strftime('%Y-%m'),
        label: I18n.l(start, format: '%b/%y'),
        entradas: ent,
        saidas: sai,
        lucro: ent - sai
      }
    end
  end

  # ----------------------------------------------------------------
  # DRE helpers
  # ----------------------------------------------------------------

  def resolve_dre_period
    case params[:period]
    when 'quarter'
      anchor = params[:date].present? ? Date.parse("#{params[:date]}-01") : Time.zone.today
      start  = anchor.beginning_of_quarter
      start..start.end_of_quarter
    when 'year'
      anchor = params[:date].present? ? Date.parse("#{params[:date]}-01-01") : Time.zone.today
      start  = anchor.beginning_of_year
      start..start.end_of_year
    when 'custom'
      Date.parse(params[:start_date])..Date.parse(params[:end_date])
    else # 'month' (default)
      anchor = params[:date].present? ? Date.parse("#{params[:date]}-01") : Time.zone.today
      anchor.all_month
    end
  end

  def prior_period(period)
    length = (period.last - period.first).to_i + 1
    prior_end   = period.first - 1
    prior_start = prior_end - length + 1
    prior_start..prior_end
  end

  # Returns a structured DRE hash for the given account and date range.
  # Uses competence_date (regime de competência), not received_at/paid_at.
  def build_dre(account, period)
    scope = base_scope(account).competencia_em(period)

    income_rows    = dre_rows(scope.entradas.where(status: %w[recebido pendente parcial]), period)
    expense_rows   = dre_rows(scope.saidas.where(status: %w[pago pendente parcial]), period)

    receita_bruta  = income_rows.sum { |r| r[:amount] }
    deducoes       = income_rows.select { |r| r[:category_type] == 'deducao' }.sum { |r| r[:amount] }
    receita_liq    = receita_bruta - deducoes

    custos_var     = expense_rows.select { |r| r[:cost_type] == 'variavel' }.sum { |r| r[:amount] }
    margem_bruta   = receita_liq - custos_var

    desp_fixas     = expense_rows.select { |r| r[:cost_type] == 'fixo' }.sum { |r| r[:amount] }
    ebitda         = margem_bruta - desp_fixas

    outras_desp    = expense_rows.reject { |r| %w[fixo variavel].include?(r[:cost_type]) }.sum { |r| r[:amount] }
    lucro_liq      = ebitda - outras_desp

    {
      receita_bruta: receita_bruta,
      deducoes: deducoes,
      receita_liq: receita_liq,
      custos_var: custos_var,
      margem_bruta: margem_bruta,
      desp_fixas: desp_fixas,
      ebitda: ebitda,
      outras_desp: outras_desp,
      lucro_liq: lucro_liq,
      income_rows: income_rows,
      expense_rows: expense_rows
    }
  end

  def dre_rows(scope, _period)
    scope
      .joins('LEFT JOIN financial_categories ON financial_categories.id = account_transactions.financial_category_id')
      .group('financial_categories.id', 'financial_categories.name', 'financial_categories.cost_type',
             'financial_categories.category_type', 'financial_categories.color')
      .select(
        'financial_categories.id        AS fc_id',
        'financial_categories.name      AS fc_name',
        'financial_categories.cost_type AS fc_cost_type',
        'financial_categories.category_type AS fc_category_type',
        'financial_categories.color     AS fc_color',
        'SUM(account_transactions.amount) AS total_amount'
      )
      .map do |row|
        {
          category_id: row.fc_id,
          category_name: row.fc_name || 'Sem categoria',
          cost_type: row.fc_cost_type,
          category_type: row.fc_category_type,
          color: row.fc_color || '#64748b',
          amount: row.total_amount.to_f
        }
      end
  end
  # ----------------------------------------------------------------
  # Insurance helpers
  # ----------------------------------------------------------------

  def insurance_rows(account, period)
    base_scope(account)
      .entradas
      .where(status: %w[recebido], received_at: period)
      .joins(<<~SQL.squish)
        LEFT JOIN financial_categories fc
          ON fc.id = account_transactions.financial_category_id
      SQL
      .group('COALESCE(account_transactions.metadata ->> \'insurance\', fc.name, \'Particular\')')
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

  # ----------------------------------------------------------------
  # Average Ticket helpers
  # ----------------------------------------------------------------

  def ticket_by_professional(account, period)
    base_scope(account)
      .entradas
      .recebidos
      .where(received_at: period)
      .where.not(professional_id: nil)
      .joins('LEFT JOIN users ON users.id = account_transactions.professional_id')
      .group('account_transactions.professional_id', 'users.name')
      .select(
        'account_transactions.professional_id',
        'users.name AS professional_name',
        'COUNT(*) AS txn_count',
        'SUM(account_transactions.amount) AS total_amount',
        'AVG(account_transactions.amount) AS avg_amount'
      )
      .map do |row|
        {
          professional_id: row.professional_id,
          professional_name: row.professional_name || 'Sem profissional',
          count: row.txn_count.to_i,
          total: row.total_amount.to_f,
          ticket: row.avg_amount.to_f
        }
      end
      .sort_by { |r| -r[:ticket] }
  end

  def ticket_by_month(account, period)
    base_scope(account)
      .entradas
      .recebidos
      .where(received_at: period)
      .group("DATE_TRUNC('month', received_at)")
      .select(
        "DATE_TRUNC('month', received_at) AS month_start",
        'COUNT(*) AS txn_count',
        'SUM(amount) AS total_amount',
        'AVG(amount) AS avg_amount'
      )
      .map do |r|
        dt = r.month_start.to_date
        {
          month: dt.strftime('%Y-%m'),
          label: I18n.l(dt, format: '%b/%y'),
          count: r.txn_count.to_i,
          total: r.total_amount.to_f,
          ticket: r.avg_amount.to_f
        }
      end
      .sort_by { |r| r[:month] }
  end

  def ticket_overall(account, period)
    scope = base_scope(account).entradas.recebidos.where(received_at: period)
    count = scope.count
    total = scope.sum(:amount).to_f
    { count: count, total: total, ticket: count.positive? ? total / count : 0.0 }
  end

  # ----------------------------------------------------------------
  # CSV builders
  # ----------------------------------------------------------------

  def build_commissions_csv(result, professional)
    rows  = result[:transactions] || []
    lines = []
    lines << "Profissional: #{professional.name}"
    lines << "Período: #{result.dig(:period, :start)} a #{result.dig(:period, :end)}"
    lines << ''
    lines << 'Data,Descrição,Tipo Regra,Valor Transação,Comissão'
    rows.each do |tx|
      lines << [
        tx[:date], tx[:description], tx[:rule_type],
        tx[:transaction_amount], tx[:commission_amount]
      ].join(',')
    end
    lines << ''
    lines << "Total de Comissão:,#{result[:total_commission]}"
    lines.join("\n")
  end

  def build_insurance_csv(result)
    lines = []
    lines << "Período: #{result.dig(:period, :start)} a #{result.dig(:period, :end)}"
    lines << ''
    lines << 'Convênio/Origem,Quantidade,Total (R$)'
    result[:rows].each do |r|
      lines << [r[:label], r[:count], r[:amount]].join(',')
    end
    lines << ''
    lines << "Total:,#{result[:count]},#{result[:total]}"
    lines.join("\n")
  end
end
