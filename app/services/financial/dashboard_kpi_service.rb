class Financial::DashboardKpiService
  def initialize(account:)
    @account = account
  end

  def call
    kpi_values.merge(sparklines: sparklines_payload)
  end

  private

  def kpi_values
    today = Time.zone.today
    yesterday = today - 1
    e_hoje  = entradas_on(today)
    e_ontem = entradas_on(yesterday)
    s_hoje  = saidas_on(today)
    s_ontem = saidas_on(yesterday)

    {
      entradas_hoje: e_hoje,
      entradas_variacao: variacao(e_hoje, e_ontem),
      saidas_hoje: s_hoje,
      saidas_variacao: variacao(s_hoje, s_ontem),
      saldo_dia: saldo_contas,
      inadimplencia_total: inadimplencia_total
    }
  end

  def sparklines_payload
    {
      entradas: sparkline_entradas,
      saidas: sparkline_saidas,
      saldo: sparkline_saldo,
      inadimplencia: sparkline_inadimplencia
    }
  end

  def base_scope
    @account.account_transactions.kept
  end

  def entradas_on(date)
    base_scope.where(entry_type: 'entrada', status: 'recebido')
              .where(received_at: date.all_day)
              .sum(:amount).to_f
  end

  def saidas_on(date)
    base_scope.where(entry_type: 'saida', status: 'pago')
              .where(paid_at: date.all_day)
              .sum(:amount).to_f
  end

  def saldo_contas
    @account.bank_accounts.active.sum(&:current_balance).to_f
  end

  def inadimplencia_total
    base_scope.where(entry_type: 'entrada', status: 'pendente')
              .where('due_date < ?', Time.zone.today)
              .sum(:amount).to_f
  end

  def variacao(atual, anterior)
    return 0.0 if anterior.zero?

    ((atual - anterior) / anterior * 100).round(1)
  end

  def sparkline_entradas
    7.downto(0).map do |n|
      day = Time.zone.today - n
      entradas_on(day)
    end
  end

  def sparkline_saidas
    7.downto(0).map do |n|
      day = Time.zone.today - n
      saidas_on(day)
    end
  end

  def sparkline_saldo
    # Saldo acumulado diário dos últimos 8 dias
    saldo = @account.bank_accounts.active.sum(:initial_balance).to_f
    7.downto(0).map do |n|
      day = Time.zone.today - n
      e   = entradas_on(day)
      s   = saidas_on(day)
      saldo += (e - s)
      saldo.round(2)
    end
  end

  def sparkline_inadimplencia
    7.downto(0).map do |n|
      cutoff = Time.zone.today - n
      base_scope.where(entry_type: 'entrada', status: 'pendente')
                .where('due_date < ?', cutoff)
                .sum(:amount).to_f
    end
  end
end
