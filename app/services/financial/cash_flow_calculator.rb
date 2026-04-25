class Financial::CashFlowCalculator
  def initialize(account:, start_date:, end_date:, bank_account_id: nil)
    @account = account
    @start_date = start_date.to_date
    @end_date = end_date.to_date
    @bank_account_id = bank_account_id
  end

  def call
    entradas_map = entradas_by_day
    saidas_map   = saidas_by_day
    saldo_acumulado = opening_balance

    (@start_date..@end_date).map do |day|
      e = entradas_map[day] || 0.0
      s = saidas_map[day] || 0.0
      saldo_acumulado += (e - s)

      {
        date: day.to_s,
        label: I18n.l(day, format: '%d/%m'),
        entradas: e.round(2),
        saidas: s.round(2),
        saldo_acumulado: saldo_acumulado.round(2)
      }
    end
  end

  private

  def base_scope
    scope = @account.account_transactions.kept
    scope = scope.where(bank_account_id: @bank_account_id) if @bank_account_id.present?
    scope
  end

  def entradas_by_day
    base_scope
      .where(entry_type: 'entrada', status: 'recebido')
      .where(received_at: @start_date..@end_date.end_of_day)
      .group('date(received_at)')
      .sum(:amount)
      .transform_keys(&:to_date)
      .transform_values(&:to_f)
  end

  def saidas_by_day
    base_scope
      .where(entry_type: 'saida', status: 'pago')
      .where(paid_at: @start_date..@end_date.end_of_day)
      .group('date(paid_at)')
      .sum(:amount)
      .transform_keys(&:to_date)
      .transform_values(&:to_f)
  end

  # Saldo acumulado até o dia anterior ao período
  def opening_balance
    day_before = @start_date - 1
    scope = @account.account_transactions.kept
    scope = scope.where(bank_account_id: @bank_account_id) if @bank_account_id.present?

    ent = scope.where(entry_type: 'entrada', status: 'recebido')
               .where(received_at: ..day_before.end_of_day)
               .sum(:amount).to_f
    sai = scope.where(entry_type: 'saida', status: 'pago')
               .where(paid_at: ..day_before.end_of_day)
               .sum(:amount).to_f
    initial = @account.bank_accounts.active.sum(:initial_balance).to_f
    initial + ent - sai
  end
end
