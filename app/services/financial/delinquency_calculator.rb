class Financial::DelinquencyCalculator
  AGING_BANDS = [
    { label: '1-30 dias',  range: 1..30 },
    { label: '31-60 dias', range: 31..60 },
    { label: '61-90 dias', range: 61..90 },
    { label: '90+ dias',   range: 91..Float::INFINITY }
  ].freeze

  def initialize(account:)
    @account = account
    @today   = Time.zone.today
  end

  # Gráfico 6: aging por faixa de dias
  def aging
    overdue = overdue_records
    total   = overdue.sum { |r| r[:amount] }

    AGING_BANDS.map do |band|
      subset = overdue.select { |r| band[:range].include?(r[:days]) }
      valor  = subset.sum { |r| r[:amount] }
      {
        faixa: band[:label],
        valor: valor.round(2),
        pacientes: subset.map { |r| r[:patient_id] }.uniq.size,
        percentual: total.positive? ? (valor / total * 100).round(1) : 0.0
      }
    end
  end

  # Gráfico 7: tendência mensal dos últimos N meses
  def trend(months: 12)
    months.downto(1).map do |n|
      ref   = @today - (n - 1).months
      mes   = ref.strftime('%Y-%m')
      start_of = ref.beginning_of_month
      end_of   = ref.end_of_month

      inadimplente = overdue_for_month(start_of, end_of)
      receita      = revenue_for_month(start_of, end_of)
      pct          = receita.positive? ? (inadimplente / receita * 100).round(1) : 0.0

      {
        mes: mes,
        valor_inadimplente: inadimplente.round(2),
        receita_bruta: receita.round(2),
        percentual: pct
      }
    end
  end

  # Gráfico 8: inadimplência por profissional
  def by_professional(period: nil)
    ref_month = period.present? ? Date.parse("#{period}-01") : @today.beginning_of_month
    rows = overdue_by_professional_rows
    delinquency_rows(rows, ref_month).sort_by { |r| -r[:percentual] }
  end

  private

  def overdue_by_professional_rows
    @account.account_transactions.kept
            .where(entry_type: 'entrada', status: 'pendente')
            .where('due_date < ?', @today)
            .where.not(professional_id: nil)
            .joins('INNER JOIN users ON users.id = account_transactions.professional_id')
            .group('users.id', 'users.name')
            .select('users.id AS professional_id, users.name AS nome, SUM(account_transactions.amount) AS inadimplente')
  end

  def delinquency_rows(rows, ref_month)
    rows.map do |row|
      producao = producao_for(row.professional_id, ref_month)
      pct      = producao.positive? ? (row.inadimplente.to_f / producao * 100).round(1) : 0.0
      { professional_id: row.professional_id, nome: row.nome,
        inadimplente: row.inadimplente.to_f.round(2), producao: producao.round(2), percentual: pct }
    end
  end

  def overdue_records
    @overdue_records ||=
      @account.account_transactions.kept
              .where(entry_type: 'entrada', status: 'pendente')
              .where('due_date < ?', @today)
              .select(:id, :amount, :due_date, :patient_id)
              .map do |r|
                {
                  amount: r.amount.to_f,
                  days: (@today - r.due_date.to_date).to_i,
                  patient_id: r.patient_id
                }
              end
  end

  def overdue_for_month(start_of, end_of)
    @account.account_transactions.kept
            .where(entry_type: 'entrada', status: 'pendente')
            .where(due_date: start_of..end_of)
            .where('due_date < ?', @today)
            .sum(:amount).to_f
  end

  def revenue_for_month(start_of, end_of)
    @account.account_transactions.kept
            .where(entry_type: 'entrada', status: 'recebido')
            .where(received_at: start_of..end_of.end_of_day)
            .sum(:amount).to_f
  end

  def producao_for(professional_id, ref_month)
    @account.account_transactions.kept
            .where(entry_type: 'entrada', status: 'recebido')
            .where(professional_id: professional_id)
            .where(received_at: ref_month.beginning_of_month..ref_month.end_of_month.end_of_day)
            .sum(:amount).to_f
  end
end
