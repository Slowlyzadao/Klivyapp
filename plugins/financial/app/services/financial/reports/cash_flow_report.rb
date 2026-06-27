module Financial
  module Reports
    # Fluxo de Caixa — regime caixa (filtra por cash_date).
    # Canon §6 (Fluxo) + §6.1 (Saldo Líquido vs Saldo em Caixa).
    class CashFlowReport
      attr_reader :account, :from, :to, :bank_account_id

      def self.call(**kwargs) = new(**kwargs).call

      def initialize(account:, from:, to:, bank_account_id: nil)
        @account = account
        @from = from.to_date
        @to = to.to_date
        @bank_account_id = bank_account_id
      end

      def call
        scope = Financial::Entry
                .for_account(@account.id)
                .for_cashflow
                .on_cash_date(@from, @to)
        scope = scope.where(financial_bank_account_id: @bank_account_id) if @bank_account_id

        income_total  = scope.income.sum(:amount_cents)
        outflow_total = scope.outflow.sum(:amount_cents)
        net_period    = income_total - outflow_total

        {
          period: { from: @from, to: @to },
          income_cents: income_total,
          outflow_cents: outflow_total,
          net_period_cents: net_period,
          available_balance_cents: available_balance,
          daily: daily_breakdown(scope)
        }
      end

      def daily_breakdown(scope)
        rows = scope
               .group(:cash_date, :direction)
               .sum(:amount_cents)

        dates = (@from..@to).to_a
        running = 0
        dates.map do |date|
          inc = rows[[date, 'in']].to_i
          out = rows[[date, 'out']].to_i
          running += inc - out
          { date: date, income_cents: inc, outflow_cents: out, net_cents: inc - out, running_cents: running }
        end
      end

      # "Saldo Disponível Hoje" = SOMA dos saldos atuais de todas as contas
      # que afetam o DRE (exclui CARD_RECEIVABLE para evitar contar dinheiro que
      # ainda não chegou). Canon §6.1 (renomeado de "Saldo em Caixa").
      def available_balance
        accounts = Financial::BankAccount
                   .for_account(@account.id)
                   .active_accounts
                   .for_dre
        accounts.sum(&:current_balance_cents)
      end
    end
  end
end
