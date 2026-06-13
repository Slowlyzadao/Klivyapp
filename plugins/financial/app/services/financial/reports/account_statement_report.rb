module Financial
  module Reports
    # Extrato por Conta — canon Hub Relatórios (2026-05-23).
    #
    # Lista TODAS as Entries de uma conta bancária num período,
    # cronologicamente, com saldo corrente após cada movimento. Visão de
    # extrato bancário tradicional (mais antiga em cima na lista, com saldo
    # acumulando) — usado pra auditoria de movimentação por conta.
    #
    # Saldo inicial é estimado: saldo atual da conta MENOS soma das entries
    # do período (não temos snapshot histórico real, então reconstruímos).
    # Operações futuras de fechamento mensal vão persistir o saldo real
    # como ponto de partida.
    #
    # Retorno:
    #   {
    #     period:        { from:, to: },
    #     bank_account:  { id, name, kind, current_balance_cents },
    #     summary:       { initial_balance_cents:, income_cents:, outflow_cents:,
    #                      final_balance_cents:, transactions_count: },
    #     entries:       [{ date:, kind:, kind_label:, description:, direction:,
    #                       amount_cents:, signed_amount_cents:, balance_cents: }]
    #   }
    class AccountStatementReport
      KIND_LABELS = {
        'receita'         => 'Receita',
        'despesa'         => 'Despesa',
        'transferencia'   => 'Transferência',
        'sangria'         => 'Sangria',
        'suprimento'      => 'Suprimento',
        'quebra_caixa'    => 'Quebra de caixa',
        'estorno_receita' => 'Estorno de receita',
        'estorno_despesa' => 'Estorno de despesa',
        'juros'           => 'Juros',
        'multa'           => 'Multa',
        'desconto'        => 'Desconto',
        'manual_entry'    => 'Lançamento avulso',
        'mdr_fee'         => 'Taxa MDR'
      }.freeze

      def self.call(**kwargs) = new(**kwargs).call

      def initialize(account:, bank_account_id:, from:, to:)
        @account = account
        @bank_account_id = bank_account_id.to_i
        @from = from.to_date
        @to   = to.to_date
      end

      def call
        bank = Financial::BankAccount.for_account(@account.id).find_by(id: @bank_account_id)
        return empty_response unless bank

        # Entries do período, ordenadas por cash_date ASC (extrato é
        # cronológico crescente — saldo construído de baixo pra cima).
        period_entries = Financial::Entry
                           .for_account(@account.id)
                           .where(financial_bank_account_id: bank.id)
                           .for_cashflow
                           .on_cash_date(@from, @to)
                           .order(:cash_date, :id)
                           .to_a

        # Saldo inicial reconstruído a partir do saldo atual da conta
        # MENOS movimentações futuras (depois do `to`) MAIS movimentações
        # passadas (até antes do `from`). Equivalente a "saldo no dia
        # anterior ao `from`".
        current_balance = bank.current_balance_cents.to_i

        # Soma TODAS as entries depois do período + as do próprio período
        # (pra subtrair do saldo atual e chegar no "antes").
        after_period = Financial::Entry
                         .for_account(@account.id)
                         .where(financial_bank_account_id: bank.id)
                         .for_cashflow
                         .where('cash_date > ?', @to)
        period_signed = period_entries.sum { |e| signed_amount(e) }
        after_period_signed = after_period.sum { |e| signed_amount(e) }

        initial_balance = current_balance - period_signed - after_period_signed

        running = initial_balance
        rows = period_entries.map do |e|
          signed = signed_amount(e)
          running += signed
          {
            id: e.id,
            date: e.cash_date.iso8601,
            kind: e.kind,
            kind_label: KIND_LABELS[e.kind] || e.kind.to_s.humanize,
            direction: e.direction,
            description: e.description,
            amount_cents: e.amount_cents.to_i,
            signed_amount_cents: signed,
            balance_cents: running
          }
        end

        income = period_entries.select { |e| e.direction == 'in' }.sum(&:amount_cents).to_i
        outflow = period_entries.select { |e| e.direction == 'out' }.sum(&:amount_cents).to_i

        {
          period: { from: @from.iso8601, to: @to.iso8601 },
          bank_account: {
            id: bank.id,
            name: bank.name,
            kind: bank.kind,
            current_balance_cents: current_balance
          },
          summary: {
            initial_balance_cents: initial_balance,
            income_cents: income,
            outflow_cents: outflow,
            final_balance_cents: running,
            transactions_count: rows.size
          },
          entries: rows
        }
      end

      private

      def signed_amount(entry)
        sign = entry.direction == 'in' ? 1 : -1
        sign * entry.amount_cents.to_i
      end

      def empty_response
        {
          period: { from: @from.iso8601, to: @to.iso8601 },
          bank_account: nil,
          summary: { initial_balance_cents: 0, income_cents: 0, outflow_cents: 0,
                     final_balance_cents: 0, transactions_count: 0 },
          entries: []
        }
      end
    end
  end
end
