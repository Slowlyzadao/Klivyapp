class Financial::RevenueGoalCalculator
  def initialize(account:, month:)
    @account = account
    @month   = month.beginning_of_month
  end

  def call
    meta            = @account.monthly_goal.to_f
    meta_trimestral = @account.quarterly_goal.to_f
    meta_anual      = @account.annual_goal.to_f

    realizado            = realized_amount_for(@month..@month.end_of_month.end_of_day)
    realizado_trimestral = realized_amount_for(@month.beginning_of_quarter..@month.end_of_quarter.end_of_day)
    realizado_anual      = realized_amount_for(@month.beginning_of_year..@month.end_of_year.end_of_day)

    {
      meta: meta,
      meta_trimestral: meta_trimestral,
      meta_anual: meta_anual,
      realizado: realizado.round(2),
      realizado_trimestral: realizado_trimestral.round(2),
      realizado_anual: realizado_anual.round(2),
      percentual: compute_pct(realizado, meta),
      percentual_trimestral: compute_pct(realizado_trimestral, meta_trimestral),
      percentual_anual: compute_pct(realizado_anual, meta_anual),
      ritmo_ideal: ideal_pace(meta, :month).round(2),
      delta_ritmo: (realizado - ideal_pace(meta, :month)).round(2),
      dias_restantes: remaining_days(:month),
      ritmo_ideal_trimestral: ideal_pace(meta_trimestral, :quarter).round(2),
      delta_ritmo_trimestral: (realizado_trimestral - ideal_pace(meta_trimestral, :quarter)).round(2),
      dias_restantes_trimestral: remaining_days(:quarter),
      ritmo_ideal_anual: ideal_pace(meta_anual, :year).round(2),
      delta_ritmo_anual: (realizado_anual - ideal_pace(meta_anual, :year)).round(2),
      dias_restantes_anual: remaining_days(:year)
    }
  end

  private

  def realized_amount_for(date_range)
    base_scope
      .where(entry_type: 'entrada', status: 'recebido')
      .where(received_at: date_range)
      .sum(:amount).to_f
  end

  def ideal_pace(meta, period)
    return 0.0 unless meta.positive?
    total   = total_days(period)
    elapsed = elapsed_days(period)
    meta / total * elapsed
  end

  def elapsed_days(period)
    today = Time.zone.today
    start_date = start_of_period(period)
    end_date   = end_of_period(period)

    return total_days(period) if today > end_date
    return 0 if today < start_date

    (today - start_date).to_i + 1
  end

  def total_days(period)
    (end_of_period(period) - start_of_period(period)).to_i + 1
  end

  def remaining_days(period)
    total_days(period) - elapsed_days(period)
  end

  def start_of_period(period)
    case period
    when :month   then @month
    when :quarter then @month.beginning_of_quarter
    when :year    then @month.beginning_of_year
    end
  end

  def end_of_period(period)
    case period
    when :month   then @month.end_of_month
    when :quarter then @month.end_of_quarter
    when :year    then @month.end_of_year
    end
  end

  def compute_pct(realizado, meta)
    return 0.0 unless meta.positive?

    [(realizado / meta * 100).round(1), 100.0].min
  end

  def base_scope
    @account.account_transactions.kept
  end
end
