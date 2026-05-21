class Financial::CashFlowProjectionService
  PESSIMISM_MONTHS = 3

  def initialize(account:, horizon: 30, bank_account_id: nil)
    @account = account
    @horizon = horizon.to_i.clamp(1, 90)
    @bank_account_id = bank_account_id
    @today = Time.zone.today
  end

  def call
    {
      atual: current_balance,
      projecao: project_days
    }
  end

  private

  def current_balance
    scope = @account.bank_accounts.active
    scope = scope.where(id: @bank_account_id) if @bank_account_id.present?
    scope.sum(&:current_balance).to_f
  end

  def delinquency_rate
    months_ago = @today - PESSIMISM_MONTHS.months
    receita = @account.account_transactions.kept
                      .where(entry_type: 'entrada', status: 'recebido')
                      .where(received_at: months_ago..@today.end_of_day)
                      .sum(:amount).to_f
    return 0.0 if receita.zero?

    inadimplente = @account.account_transactions.kept
                           .where(entry_type: 'entrada', status: 'pendente')
                           .where('due_date < ?', @today)
                           .sum(:amount).to_f
    [inadimplente / receita, 0.5].min
  end

  def receivables_by_day
    @receivables_by_day ||=
      @account.account_transactions.kept
              .where(entry_type: 'entrada', status: 'pendente')
              .where(due_date: @today..(@today + @horizon.days))
              .group(:due_date)
              .sum(:amount)
              .transform_values(&:to_f)
  end

  def payables_by_day
    @payables_by_day ||=
      @account.account_transactions.kept
              .where(entry_type: 'saida')
              .where(status: %w[pendente a_pagar])
              .where(due_date: @today..(@today + @horizon.days))
              .group(:due_date)
              .sum(:amount)
              .transform_values(&:to_f)
  end

  def recurring_by_day
    @recurring_by_day ||= build_recurring_map
  end

  def build_recurring_map
    map = Hash.new(0.0)
    horizon_end = @today + @horizon.days
    @account.recurring_expenses.active.each do |rec|
      date = rec.next_due_date(@today - 1)
      while date && date <= horizon_end
        map[date] += rec.amount.to_f if date >= @today
        date = rec.next_due_date(date)
      end
    end
    map
  end

  def project_days
    saldo = current_balance
    rate  = delinquency_rate

    (@today..(@today + @horizon.days)).map do |day|
      entry = project_day_entry(day, saldo, rate)
      saldo = entry[:central]
      entry
    end
  end

  def project_day_entry(day, saldo, rate)
    rec = receivables_by_day[day] || 0.0
    pay = (payables_by_day[day] || 0.0) + (recurring_by_day[day] || 0.0)
    {
      date: day.to_s,
      central: (saldo + ((rec * (1 - (rate * 0.5))) - pay)).round(2),
      otimista: (saldo + rec - pay).round(2),
      pessimista: (saldo + ((rec * (1 - rate)) - pay)).round(2)
    }
  end
end
