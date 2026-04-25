# frozen_string_literal: true

# PDF: Faturamento por Convênio — insurance/provider revenue report.
class Financial::Pdf::InsurancePdf < Financial::Pdf::BasePdf
  def initialize(account:, period:)
    super(account: account)
    @period = period
  end

  private

  def build
    rows  = fetch_insurance_data
    total = rows.sum { |r| r[:amount] }
    count = rows.sum { |r| r[:count] }
    avg   = count > 0 ? total / count : 0.0

    draw_header(
      title: 'Faturamento por Convênio',
      subtitle: 'Análise de receitas segmentadas por convênio ou origem de pagamento.',
      period_label: "#{fmt_date(@period.first)} a #{fmt_date(@period.last)}"
    )

    draw_kpi_cards([
      { label: 'Total Faturado',   value: fmt(total),      color: BRAND_GREEN, bg: 'f0fdf4' },
      { label: 'Atendimentos',     value: count.to_s,       color: BRAND_BLUE,  bg: 'eff6ff' },
      { label: 'Ticket Médio',     value: fmt(avg),         color: BRAND_BLUE,  bg: 'eff6ff' },
      { label: 'Convênios',        value: rows.size.to_s,   color: BRAND_GRAY,  bg: 'f8fafc' }
    ])

    draw_section_title('Ranking por Convênio')
    draw_insurance_table(rows, total)

    draw_total_row('FATURAMENTO TOTAL', fmt(total), color: BRAND_GREEN)
  end

  def fetch_insurance_data
    account.account_transactions.kept
           .entradas
           .where(status: 'recebido', received_at: @period)
           .joins(<<~SQL.squish)
             LEFT JOIN financial_categories fc
               ON fc.id = account_transactions.financial_category_id
           SQL
           .group("COALESCE(account_transactions.metadata ->> 'insurance', fc.name, 'Particular')")
           .select(
             "COALESCE(account_transactions.metadata ->> 'insurance', fc.name, 'Particular') AS label",
             'COUNT(*) AS txn_count',
             'SUM(account_transactions.amount) AS total_amount'
           )
           .map do |row|
             {
               label: row.label,
               count: row.txn_count.to_i,
               amount: row.total_amount.to_f
             }
           end
           .sort_by { |r| -r[:amount] }
  end

  def draw_insurance_table(rows, total)
    headers = ['#', 'Convênio / Origem', 'Atendimentos', 'Total Faturado', 'Ticket Médio', '% do Total']

    table_rows = rows.each_with_index.map do |r, i|
      pct = total > 0 ? (r[:amount] / total * 100).round(1) : 0.0
      avg = r[:count] > 0 ? r[:amount] / r[:count] : 0.0
      [
        (i + 1).to_s,
        r[:label],
        r[:count].to_s,
        fmt(r[:amount]),
        fmt(avg),
        "#{pct}%"
      ]
    end

    draw_styled_table(headers, table_rows,
                      number_columns: [0, 2, 3, 4, 5],
                      empty_message: 'Nenhum faturamento por convênio encontrado.')
  end
end
