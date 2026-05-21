# frozen_string_literal: true

# PDF: Ticket Médio — average ticket report by professional or month.
class Financial::Pdf::AverageTicketPdf < Financial::Pdf::BasePdf
  def initialize(account:, period:, group_by: 'professional')
    super(account: account)
    @period   = period
    @group_by = group_by
  end

  private

  def build
    overall = fetch_overall
    rows    = @group_by == 'month' ? fetch_by_month : fetch_by_professional

    draw_header(
      title: 'Relatório de Ticket Médio',
      subtitle: "Agrupado por #{@group_by == 'month' ? 'mês' : 'profissional'}.",
      period_label: "#{fmt_date(@period.first)} a #{fmt_date(@period.last)}"
    )

    draw_kpi_cards([
      { label: 'Ticket Médio Geral',  value: fmt(overall[:ticket]),   color: BRAND_BLUE,  bg: 'eff6ff' },
      { label: 'Total Faturado',      value: fmt(overall[:total]),    color: BRAND_GREEN, bg: 'f0fdf4' },
      { label: 'Atendimentos',        value: overall[:count].to_s,    color: BRAND_GRAY,  bg: 'f8fafc' },
      { label: @group_by == 'month' ? 'Meses' : 'Profissionais', value: rows.size.to_s, color: BRAND_BLUE, bg: 'eff6ff' }
    ])

    draw_section_title("Detalhamento por #{@group_by == 'month' ? 'Mês' : 'Profissional'}")

    if @group_by == 'month'
      draw_month_table(rows)
    else
      draw_professional_table(rows)
    end

    draw_total_row('TICKET MÉDIO GERAL', fmt(overall[:ticket]), color: BRAND_BLUE)
  end

  def fetch_overall
    scope = base_scope
    count = scope.count
    total = scope.sum(:amount).to_f
    { count: count, total: total, ticket: count > 0 ? total / count : 0.0 }
  end

  def fetch_by_professional
    base_scope
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
      .map do |r|
        {
          name: r.professional_name || 'Sem profissional',
          count: r.txn_count.to_i,
          total: r.total_amount.to_f,
          ticket: r.avg_amount.to_f
        }
      end
      .sort_by { |r| -r[:ticket] }
  end

  def fetch_by_month
    base_scope
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
          name: I18n.l(dt, format: '%B/%Y').capitalize,
          count: r.txn_count.to_i,
          total: r.total_amount.to_f,
          ticket: r.avg_amount.to_f
        }
      end
      .sort_by { |r| r[:name] }
  end

  def draw_professional_table(rows)
    headers = ['#', 'Profissional', 'Atendimentos', 'Total Faturado', 'Ticket Médio']

    table_rows = rows.each_with_index.map do |r, i|
      [(i + 1).to_s, r[:name], r[:count].to_s, fmt(r[:total]), fmt(r[:ticket])]
    end

    draw_styled_table(headers, table_rows,
                      number_columns: [0, 2, 3, 4],
                      empty_message: 'Nenhum profissional com atendimentos no período.')
  end

  def draw_month_table(rows)
    headers = ['Mês', 'Atendimentos', 'Total Faturado', 'Ticket Médio']

    table_rows = rows.map do |r|
      [r[:name], r[:count].to_s, fmt(r[:total]), fmt(r[:ticket])]
    end

    draw_styled_table(headers, table_rows,
                      number_columns: [1, 2, 3],
                      empty_message: 'Nenhum dado disponível para o período.')
  end

  def base_scope
    account.account_transactions.kept
           .entradas.recebidos
           .where(received_at: @period)
  end
end
