# frozen_string_literal: true

# PDF: Despesas por Categoria — expense breakdown report.
class Financial::Pdf::ExpensesByCategoryPdf < Financial::Pdf::BasePdf
  def initialize(account:, period: nil)
    super(account: account)
    @period_param = period || Time.zone.today.strftime('%Y-%m')
  end

  private

  def build
    range    = resolve_period
    expenses = fetch_expenses(range)
    total    = expenses.sum { |r| r[:amount] }

    draw_header(
      title: 'Relatório de Despesas por Categoria',
      subtitle: 'Distribuição detalhada das despesas operacionais da sua clínica.',
      period_label: "#{fmt_date(range.first)} a #{fmt_date(range.last)}"
    )

    draw_kpi_cards([
      { label: 'Total de Despesas',  value: fmt(total),            color: BRAND_RED,  bg: 'fef2f2' },
      { label: 'Categorias',         value: expenses.size.to_s,    color: BRAND_BLUE, bg: 'eff6ff' },
      { label: 'Maior Despesa',      value: fmt(expenses.first&.dig(:amount) || 0), color: BRAND_RED, bg: 'fef2f2' },
      { label: 'Menor Despesa',      value: fmt(expenses.last&.dig(:amount) || 0),  color: BRAND_GRAY, bg: 'f8fafc' }
    ])

    draw_section_title('Ranking de Despesas por Categoria')
    draw_expense_table(expenses, total)

    ensure_space(100)
    draw_section_title('Distribuição por Tipo de Custo')
    draw_cost_type_summary(expenses)

    draw_total_row('TOTAL DE DESPESAS NO PERÍODO', fmt(total), color: BRAND_RED)
  end

  def resolve_period
    ref = Date.parse("#{@period_param}-01")
    ref.beginning_of_month..ref.end_of_month
  rescue ArgumentError
    Date.today.all_month
  end

  def fetch_expenses(range)
    account.account_transactions.kept
           .where(entry_type: 'saida', status: 'pago')
           .where(paid_at: range.first..range.last.end_of_day)
           .joins('LEFT JOIN financial_categories ON financial_categories.id = account_transactions.financial_category_id')
           .group('financial_categories.name', 'financial_categories.cost_type')
           .select(
             "COALESCE(financial_categories.name, 'Sem categoria') AS fc_name",
             "COALESCE(financial_categories.cost_type, 'variavel') AS fc_cost_type",
             'COUNT(*) AS txn_count',
             'SUM(account_transactions.amount) AS total_amount'
           )
           .map do |row|
             {
               category: row.fc_name,
               cost_type: row.fc_cost_type,
               count: row.txn_count.to_i,
               amount: row.total_amount.to_f
             }
           end
           .sort_by { |r| -r[:amount] }
  end

  def draw_expense_table(expenses, total)
    headers = ['#', 'Categoria', 'Tipo', 'Qtd', 'Valor', '% do Total']

    rows = expenses.each_with_index.map do |exp, i|
      pct = total > 0 ? (exp[:amount] / total * 100).round(1) : 0.0
      [
        (i + 1).to_s,
        exp[:category],
        cost_type_label(exp[:cost_type]),
        exp[:count].to_s,
        fmt(exp[:amount]),
        "#{pct}%"
      ]
    end

    draw_styled_table(headers, rows,
                      number_columns: [0, 3, 4, 5],
                      empty_message: 'Nenhuma despesa registrada no período.')
  end

  def draw_cost_type_summary(expenses)
    groups = expenses.group_by { |e| e[:cost_type] }
    total = expenses.sum { |e| e[:amount] }

    rows = groups.map do |type, items|
      subtotal = items.sum { |e| e[:amount] }
      pct = total > 0 ? (subtotal / total * 100).round(1) : 0.0
      [cost_type_label(type), items.size.to_s, fmt(subtotal), "#{pct}%"]
    end

    draw_styled_table(
      ['Tipo de Custo', 'Categorias', 'Total', '% do Total'],
      rows,
      number_columns: [1, 2, 3]
    )
  end

  def cost_type_label(type)
    { 'fixo' => 'Custo Fixo', 'variavel' => 'Custo Variável' }[type] || 'Outro'
  end
end
