module Financial
  module Reports
    # KPIs do Dashboard. Canon §5 + corrige BUG-05 (Ticket Médio = R$ 0,00) + BUG-06 (nomes).
    class DashboardKpis
      attr_reader :account, :date, :from, :to

      def self.call(**kwargs) = new(**kwargs).call

      # Aceita 2 modos:
      #   1) `date:` (legado) — usa o mês que contém essa data como período.
      #   2) `from:`/`to:` — usa o range explícito (suporta Semana/Trimestre/Ano/Todos
      #      do period selector no frontend). Anchor `@date` continua sendo o
      #      "to" para coisas que precisam de uma data (goal mensal, scope de
      #      vencidos hoje, etc).
      #
      # `@today` é SEMPRE a data real do servidor — usado pelo card "Resultado
      # de Hoje" que precisa ser estável independente do período selecionado.
      # Bug 2026-05-12: antes usava `@date` (= @to do período); resultado:
      # selecionar Semana/Mês/etc fazia today_kpis filtrar pelo último dia do
      # período em vez do dia atual, zerando o card.
      def initialize(account:, date: nil, from: nil, to: nil)
        @account = account
        @today = Date.current
        if from.present? && to.present?
          @from = from.to_date
          @to   = to.to_date
          @date = @to
        else
          @date = (date || @today).to_date
          @from = @date.beginning_of_month
          @to   = @date.end_of_month
        end
      end

      def call
        period = { from: @from, to: @to }
        previous = previous_period(period)

        {
          period: period,
          today: today_kpis,
          month: month_kpis(period),
          comparison: comparison_kpis(period, previous),
          receivables: receivables_summary(period),
          payables: payables_summary(period),
          cash: cash_summary,
          ticket_medio: ticket_medio(period),
          revenue_goal: revenue_goal_progress(period)
        }
      end

      private

      # Período anterior = mesmo tamanho do atual, terminando no dia anterior ao
      # `from` atual. Funciona pra qualquer granularidade (semana, mês, ano,
      # custom) — comparação sempre apples-to-apples por duração.
      def previous_period(period)
        duration_days = (period[:to] - period[:from]).to_i
        prev_to = period[:from] - 1.day
        prev_from = prev_to - duration_days.days
        { from: prev_from, to: prev_to }
      end

      def month_period(date)
        { from: date.beginning_of_month, to: date.end_of_month }
      end

      def today_kpis
        # Sempre `@today` (Date.current) — o card "Hoje" é literal, não muda
        # com o período selecionado no Dashboard.
        scope = Financial::Entry
                .for_account(@account.id)
                .for_cashflow
                .on_cash_date(@today, @today)
        income  = scope.income.sum(:amount_cents)
        outflow = scope.outflow.sum(:amount_cents)
        {
          income_cents: income,
          outflow_cents: outflow,
          net_cents: income - outflow
        }
      end

      def month_kpis(period)
        cash_scope = Financial::Entry
                     .for_account(@account.id)
                     .for_cashflow
                     .on_cash_date(period[:from], period[:to])
        income  = cash_scope.income.sum(:amount_cents)
        outflow = cash_scope.outflow.sum(:amount_cents)

        comp_scope = Financial::Entry
                     .for_account(@account.id)
                     .for_dre
                     .on_competence_date(period[:from], period[:to])
        receita_competencia = comp_scope.income.sum(:amount_cents)
        despesa_competencia = comp_scope.outflow.sum(:amount_cents)

        {
          income_cents: income,
          outflow_cents: outflow,
          net_cents: income - outflow,
          receita_bruta_cents: receita_competencia,  # competência (DRE)
          despesa_total_cents: despesa_competencia,
          lucro_liquido_cents: receita_competencia - despesa_competencia
        }
      end

      def comparison_kpis(period, previous)
        current = month_kpis(period)
        prev    = month_kpis(previous)

        {
          income_var_label:  Financial::Reports::DreReport.new(
            account: @account, from: period[:from], to: period[:to]
          ).send(:var_label_for, current[:income_cents], prev[:income_cents]),
          lucro_var_label: Financial::Reports::DreReport.new(
            account: @account, from: period[:from], to: period[:to]
          ).send(:var_label_for, current[:lucro_liquido_cents], prev[:lucro_liquido_cents])
        }
      end

      def receivables_summary(period)
        # Pendentes: por due_date até o fim do período mostra "a vencer" do mês.
        pending_until = Financial::Installment
                        .for_account(@account.id)
                        .open
                        .due_until(period[:to])
        # Vencido é estado absoluto — sempre "due_date < hoje real", não muda
        # com o período selecionado no Dashboard (fix 2026-05-12; antes usava
        # @date = @to do período, zerando o KPI ao selecionar Semana/Mês/etc).
        overdue = Financial::Installment
                  .for_account(@account.id)
                  .open
                  .where('due_date < ?', @today)

        {
          pending_total_cents: pending_until.sum('amount_cents - received_amount_cents'),
          overdue_total_cents: overdue.sum('amount_cents - received_amount_cents'),
          overdue_count: overdue.count,
          new_approvals_cents: new_approvals_in_period(period)
        }
      end

      def new_approvals_in_period(period)
        Financial::Budget
          .for_account(@account.id)
          .where(approved_at: period[:from].beginning_of_day..period[:to].end_of_day)
          .sum(:total_cents)
      end

      def payables_summary(period)
        pending = Financial::Expense
                  .for_account(@account.id)
                  .open
                  .due_until(period[:to])
        recurring = Financial::Expense
                    .for_account(@account.id)
                    .recurring_origin
                    .where(due_date: period[:from]..period[:to])
        {
          pending_total_cents: pending.sum('amount_cents - paid_amount_cents'),
          recurring_total_cents: recurring.sum(:amount_cents),
          due_soon_total_cents: Financial::Expense.for_account(@account.id).due_soon(3).sum('amount_cents - paid_amount_cents')
        }
      end

      def cash_summary
        accounts = Financial::BankAccount
                   .for_account(@account.id)
                   .active_accounts
        total = accounts.for_dre.sum(&:current_balance_cents)
        {
          available_balance_cents: total,  # canon §6.1: "Saldo Disponível Hoje"
          accounts: accounts.map { |a| { id: a.id, name: a.name, kind: a.kind, balance_cents: a.current_balance_cents } }
        }
      end

      # Ticket Médio = receita ÷ transações de pagamento (PaymentReceipt) no período.
      #
      # Auditoria 2026-05-22 (`MED-CALC-02`): antes calculava receita ÷ pacientes
      # únicos. Resultado enganoso — paciente com 5 atendimentos contava como
      # 1, inflando ticket. Correto financeiramente é por TRANSAÇÃO de pagamento
      # (recibo): cada recibo = 1 evento de pagamento, normalmente cobrindo 1+
      # parcelas de um atendimento/orçamento.
      #
      # Mantém `unique_patients` no payload pra compatibilidade com FE (= count
      # de pacientes únicos no período — útil pra outras métricas).
      def ticket_medio(period)
        # Receita bruta (sem filtro de transferências — já feito pelo for_dre + scope income)
        revenue_scope = Financial::Entry
                          .for_account(@account.id)
                          .for_dre
                          .income
                          .on_competence_date(period[:from], period[:to])
                          .where.not(patient_id: nil)
                          .where.not(kind: %w[transferencia sangria suprimento])

        revenue_cents = revenue_scope.sum(:amount_cents)

        # Conta recibos no período (regime competência alinhado com revenue).
        receipts_count = Financial::PaymentReceipt
                           .for_account(@account.id)
                           .alive
                           .where(received_at: period[:from]..period[:to])
                           .count

        unique_patients = revenue_scope.distinct.count(:patient_id)

        if receipts_count.zero?
          return {
            value_cents: nil,
            receipts_count: 0,
            unique_patients: unique_patients,
            revenue_cents: revenue_cents
          }
        end

        {
          value_cents: (revenue_cents.to_f / receipts_count).round.to_i,
          receipts_count: receipts_count,
          unique_patients: unique_patients,
          revenue_cents: revenue_cents
        }
      end

      # BUG-11 fix: meta = 0 → retorna nil (frontend mostra CTA).
      # Canon Setup #8 (2026-05-23): metas agora têm datas livres + 3 tiers
      # (Mínima/Principal/Desafio) e tipos (total/por_categoria/por_agente).
      # Pra o gauge do Dashboard, pega a meta TOTAL ATIVA que cubra o período
      # selecionado (start <= period.from AND end >= period.to). Se houver
      # várias, prioriza a de menor duração (mais específica).
      #
      # `goal_cents` no payload = tier Principal (target_cents).
      # Retorna `nil` se não houver meta cobrindo o período — UI esconde gauge.
      def revenue_goal_progress(period)
        goal = ::Financial::RevenueGoal
                 .for_account(@account.id)
                 .where(kind: 'total', metric: 'currency', active: true)
                 .where('start_date <= ? AND end_date >= ?', period[:from], period[:to])
                 .order(Arel.sql('(end_date - start_date) ASC'))
                 .first

        return nil if goal.nil? || goal.target_cents.to_i.zero?

        achieved = month_kpis(period)[:receita_bruta_cents]
        progress = (achieved.to_f / goal.target_cents * 100).round(1)
        {
          kind: 'total',
          name: goal.name,
          goal_cents: goal.target_cents,
          min_goal_cents: goal.min_target_cents,
          stretch_goal_cents: goal.stretch_target_cents,
          achieved_cents: achieved,
          progress_percent: progress
        }
      end
    end
  end
end
