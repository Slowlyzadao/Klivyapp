module Financial
  module Reports
    # Serviço unificado dos 4 charts do Dashboard v2.
    #
    # Por que existem aqui (e não nos endpoints legados em
    # FinancialReportsController v1):
    #   - O importador F-10 (Clinicorp) grava em `financial_*` (v2).
    #   - Os serviços v1 (`DelinquencyCalculator`, `RevenueAnalyticsService`,
    #     `ProfessionalRevenueService`) consultam `account_transactions` (v1).
    #   - Resultado: charts puxando dos endpoints v1 ficam vazios mesmo com
    #     dados importados. Esses 4 métodos aqui leem direto das tabelas v2,
    #     alinhando o que o resto da v2 já mostra.
    module Charts
      module_function

      # ── Fluxo de Caixa Diário ─────────────────────────────────────────
      # Agrupa Financial::Entry por cash_date dentro de [from..to], com
      # entradas (direction=in), saídas (direction=out) e saldo acumulado.
      #
      # Retorno: { days: [{ date, income_cents, outflow_cents, balance_cents }] }
      def cash_flow(account:, from:, to:)
        from = from.to_date
        to   = to.to_date
        scope = Financial::Entry.for_account(account.id).for_cashflow.on_cash_date(from, to)

        rows = scope.group(:cash_date, :direction).sum(:amount_cents)
        # rows: { [date, 'in'] => sum, [date, 'out'] => sum }

        # Gera todos os dias do range pra eixo X completo (mesmo dias sem dado).
        running = 0
        days = (from..to).map do |d|
          income  = rows[[d, 'in']]  || 0
          outflow = rows[[d, 'out']] || 0
          running += income - outflow
          { date: d.iso8601, income_cents: income, outflow_cents: outflow, balance_cents: running }
        end

        { from: from.iso8601, to: to.iso8601, days: days }
      end

      # ── Composição de Receita ─────────────────────────────────────────
      # Top categorias DRE de receita em [from..to]. Inclui "Sem categoria"
      # como bucket separado (NULL = financial_dre_category_id).
      #
      # Retorno: { series: [{ category_id, label, total_cents }] } ordenado desc.
      def revenue_composition(account:, from:, to:)
        from = from.to_date
        to   = to.to_date
        scope = Financial::Entry.for_account(account.id).for_dre.income
                                .on_competence_date(from, to)
        totals = scope.group(:financial_dre_category_id).sum(:amount_cents)

        category_names = Financial::DreCategory.where(id: totals.keys.compact).pluck(:id, :name).to_h

        series = totals.map do |cid, total|
          {
            category_id: cid,
            label: cid.nil? ? 'Sem categoria' : (category_names[cid] || "Categoria #{cid}"),
            total_cents: total
          }
        end.sort_by { |s| -s[:total_cents] }

        { from: from.iso8601, to: to.iso8601, series: series }
      end

      # ── Aging Inadimplência ───────────────────────────────────────────
      # Snapshot atual: parcelas vencidas (status pendente/parcial + due_date <
      # hoje + saldo restante > 0) agrupadas por faixa de dias de atraso.
      # Não respeita from/to do period selector — aging é sempre "agora".
      #
      # Retorno: { buckets: [{ label, count, total_cents }] }
      def aging(account:)
        today = Date.current
        bands = [
          { label: '1-30 dias',  min: 1,  max: 30 },
          { label: '31-60 dias', min: 31, max: 60 },
          { label: '61-90 dias', min: 61, max: 90 },
          { label: '90+ dias',   min: 91, max: Float::INFINITY }
        ]

        installments = Financial::Installment.for_account(account.id)
                                              .where(status: %w[pendente vencido parcial])
                                              .where('due_date < ?', today)
                                              .where('amount_cents > received_amount_cents')
                                              .pluck(:due_date, Arel.sql('amount_cents - received_amount_cents'))

        buckets = bands.map { |b| { label: b[:label], count: 0, total_cents: 0 } }
        installments.each do |due_date, remaining|
          days = (today - due_date.to_date).to_i
          idx = bands.find_index { |b| days >= b[:min] && days <= b[:max] }
          next if idx.nil?

          buckets[idx][:count] += 1
          buckets[idx][:total_cents] += remaining.to_i
        end

        { buckets: buckets, total_overdue_cents: buckets.sum { |b| b[:total_cents] } }
      end

      # ── Projeção de Fluxo de Caixa ────────────────────────────────────
      # Saldo projetado dia a dia nos próximos N dias = saldo atual +
      # (a receber com due_date <= dia D) - (a pagar com due_date <= dia D).
      # Útil pro gestor antecipar quebra de caixa.
      #
      # Retorno: { current_balance_cents:, horizon_days:, days: [{date, inflow_cents, outflow_cents, balance_cents}] }
      def cash_flow_projection(account:, horizon: 60)
        today = Date.current
        end_date = today + horizon.days

        current_balance = Financial::BankAccount
                            .for_account(account.id)
                            .active_accounts
                            .for_dre
                            .sum(&:current_balance_cents)

        # A receber agrupado por dia (Installment aberta com due_date no horizonte)
        receivables = Financial::Installment
                        .for_account(account.id)
                        .open
                        .where(due_date: today..end_date)
                        .group(:due_date)
                        .sum(Arel.sql('amount_cents - received_amount_cents'))

        # A pagar agrupado por dia (Expense aberta com due_date no horizonte)
        payables = Financial::Expense
                     .for_account(account.id)
                     .where(status: %w[pendente vencido parcial])
                     .where(due_date: today..end_date)
                     .group(:due_date)
                     .sum(Arel.sql('amount_cents - paid_amount_cents'))

        running = current_balance
        days = (today..end_date).map do |d|
          inflow  = receivables[d] || 0
          outflow = payables[d]    || 0
          running += inflow - outflow
          {
            date: d.iso8601,
            inflow_cents: inflow,
            outflow_cents: outflow,
            balance_cents: running
          }
        end

        {
          current_balance_cents: current_balance,
          horizon_days: horizon,
          days: days,
          end_balance_cents: running,
          lowest_balance_cents: days.map { |d| d[:balance_cents] }.min || current_balance
        }
      end

      # ── Tendência de Inadimplência ────────────────────────────────────
      # % inadimplência mês a mês (últimos N meses) = (vencido em aberto naquele
      # mês de vencimento ÷ total faturado no mês).
      #
      # Retorno: { months:, series: [{month, label, invoiced_cents, delinquent_cents, pct}] }
      def delinquency_trend(account:, months: 12)
        today = Date.current
        series = months.downto(1).map do |n|
          ref_date = today.beginning_of_month - (n - 1).months
          month_start = ref_date.beginning_of_month
          month_end   = ref_date.end_of_month

          invoiced_cents = Financial::Installment
                             .for_account(account.id)
                             .where(competence_date: month_start..month_end)
                             .where.not(status: 'cancelado')
                             .sum(:amount_cents)

          delinquent_cents = Financial::Installment
                               .for_account(account.id)
                               .where(due_date: month_start..month_end)
                               .where('due_date < ?', today)
                               .where('amount_cents > received_amount_cents')
                               .sum(Arel.sql('amount_cents - received_amount_cents'))

          pct = invoiced_cents.positive? ? (delinquent_cents.to_f / invoiced_cents * 100).round(2) : 0.0

          {
            month: ref_date.strftime('%Y-%m'),
            label: ref_date.strftime('%m/%y'),
            invoiced_cents: invoiced_cents,
            delinquent_cents: delinquent_cents,
            pct: pct
          }
        end

        { months: months, series: series }
      end

      # ── Sparklines (14 dias) ──────────────────────────────────────────
      # Mini-séries usadas nos KPIs do Dashboard (entradas/saidas/saldo/
      # inadimplencia). Substitui o endpoint legado v1 `/financial/dashboard/
      # kpis` que lia de account_transactions.
      #
      # Retorno: { sparklines: { entradas: [...14 ints...], saidas: [...],
      #            saldo: [...], inadimplencia: [...] } }
      def kpi_sparklines(account:, days: 14)
        today = Date.current
        start_date = today - (days - 1).days

        # Entries por dia, agrupadas por direção (in/out)
        scope = Financial::Entry.for_account(account.id).for_cashflow
                                .on_cash_date(start_date, today)
        rows = scope.group(:cash_date, :direction).sum(:amount_cents)

        entradas = []
        saidas   = []
        saldo    = []
        running  = 0
        (start_date..today).each do |d|
          inc = rows[[d, 'in']]  || 0
          out = rows[[d, 'out']] || 0
          entradas << inc
          saidas   << out
          running += inc - out
          saldo << running
        end

        # Inadimplência por dia (snapshot final do dia — soma das parcelas
        # vencidas em aberto naquele momento). Aproximação leve: usa o
        # `due_date < d AND amount > received` na data D.
        inadimplencia = (start_date..today).map do |d|
          Financial::Installment.for_account(account.id)
                                .where(status: %w[pendente vencido parcial])
                                .where('due_date < ?', d)
                                .where('amount_cents > received_amount_cents')
                                .sum(Arel.sql('amount_cents - received_amount_cents'))
        end

        {
          days: days,
          sparklines: {
            entradas: entradas,
            saidas: saidas,
            saldo: saldo,
            inadimplencia: inadimplencia
          }
        }
      end

      # ── Receita por Profissional ──────────────────────────────────────
      # Soma Financial::Entry.income por professional_id em [from..to].
      # Inclui avg_ticket (receita / pacientes únicos atendidos por esse prof).
      #
      # Retorno: { professionals: [{ id, name, total_cents, count, avg_ticket_cents }] }
      def revenue_by_professional(account:, from:, to:)
        from = from.to_date
        to   = to.to_date
        scope = Financial::Entry.for_account(account.id).for_dre.income
                                .on_competence_date(from, to)
                                .where.not(professional_id: nil)

        # group by professional → { professional_id => sum_cents }
        totals = scope.group(:professional_id).sum(:amount_cents)
        return { from: from.iso8601, to: to.iso8601, professionals: [] } if totals.empty?

        # count entries per prof (para count) + pacientes únicos (para avg_ticket)
        entry_counts = scope.group(:professional_id).count
        unique_patients = scope.where.not(patient_id: nil)
                               .pluck(:professional_id, :patient_id).group_by(&:first)
                               .transform_values { |arr| arr.map(&:last).uniq.size }

        professionals = User.where(id: totals.keys).pluck(:id, :name).to_h
        rows = totals.map do |pid, total|
          uniq = unique_patients[pid] || 0
          {
            id: pid,
            name: professionals[pid] || "Usuário ##{pid}",
            total_cents: total,
            count: entry_counts[pid] || 0,
            avg_ticket_cents: uniq.positive? ? (total.to_f / uniq).round.to_i : nil
          }
        end.sort_by { |r| -r[:total_cents] }

        { from: from.iso8601, to: to.iso8601, professionals: rows }
      end
    end
  end
end
