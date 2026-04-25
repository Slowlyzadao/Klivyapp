# frozen_string_literal: true

# PDF: A Pagar — payables report with configurable pagination.
class Financial::Pdf::PayablesPdf < Financial::Pdf::BasePdf
  def initialize(account:, pages: nil, start_date: nil, end_date: nil)
    super(account: account)
    @max_pages  = pages&.to_i
    @start_date = start_date&.to_date
    @end_date   = end_date&.to_date
  end

  private

  def build
    transactions = fetch_transactions
    metrics      = calculate_metrics(transactions)

    draw_header(
      title: 'Relatório de Contas a Pagar',
      subtitle: 'Detalhamento completo das despesas e contas a pagar da sua clínica.',
      period_label: period_label
    )

    draw_kpi_cards([
      { label: 'Total a Pagar',  value: fmt(metrics[:total_pending]), color: BRAND_RED,  bg: 'fef2f2' },
      { label: 'Total Pago',     value: fmt(metrics[:total_paid]),    color: BRAND_GREEN, bg: 'f0fdf4' },
      { label: 'Vencido',        value: fmt(metrics[:total_overdue]), color: BRAND_RED,   bg: 'fef2f2' },
      { label: 'Transações',     value: metrics[:count].to_s,         color: BRAND_GRAY,  bg: 'f8fafc' }
    ])

    draw_section_title('Detalhamento das Despesas')
    draw_transactions_table(transactions)

    ensure_space(100)
    draw_section_title('Resumo por Categoria')
    draw_category_summary(transactions)

    ensure_space(100)
    draw_section_title('Resumo por Status')
    draw_status_summary(transactions)
  end

  def period_label
    if @start_date && @end_date
      "#{fmt_date(@start_date)} a #{fmt_date(@end_date)}"
    else
      'Todas as transações'
    end
  end

  def fetch_transactions
    scope = account.account_transactions.kept.saidas
    scope = scope.where(due_date: @start_date..@end_date) if @start_date && @end_date

    scope = scope.includes(:financial_category)
                 .order(due_date: :asc, created_at: :desc)

    if @max_pages
      per_page = 25
      scope = scope.limit(@max_pages * per_page)
    end

    scope.to_a
  end

  def calculate_metrics(transactions)
    pending_statuses = %w[pendente parcial]
    paid_statuses    = %w[pago]

    {
      total_pending: transactions.select { |t| pending_statuses.include?(t.status) }.sum(&:amount).to_f,
      total_paid:    transactions.select { |t| paid_statuses.include?(t.status) }.sum(&:amount).to_f,
      total_overdue: transactions.select { |t| pending_statuses.include?(t.status) && t.due_date && t.due_date < Date.today }.sum(&:amount).to_f,
      count: transactions.size
    }
  end

  def draw_transactions_table(transactions)
    headers = ['Descrição', 'Categoria', 'Valor', 'Vencimento', 'Pago em', 'Status']

    rows = transactions.map do |tx|
      status = resolve_status(tx)
      [
        truncate_text(tx.description || '—', 35),
        tx.financial_category&.name || 'Sem categoria',
        fmt(tx.amount),
        fmt_date(tx.due_date),
        fmt_date(tx.paid_at),
        status_label(status)
      ]
    end

    draw_styled_table(headers, rows,
                      number_columns: [2],
                      col_widths: { 0 => 120, 1 => 95, 2 => 70, 3 => 65, 4 => 65, 5 => 54 },
                      empty_message: 'Nenhuma conta a pagar encontrada.')
  end

  def draw_category_summary(transactions)
    groups = transactions.group_by { |t| t.financial_category&.name || 'Sem categoria' }
    rows = groups.map do |name, txs|
      total = txs.sum(&:amount).to_f
      pct = transactions.sum(&:amount).to_f > 0 ? (total / transactions.sum(&:amount).to_f * 100).round(1) : 0.0
      [name, txs.size.to_s, fmt(total), "#{pct}%"]
    end.sort_by { |r| -r[2].gsub(/[^\d,]/, '').tr(',', '.').to_f }

    draw_styled_table(
      ['Categoria', 'Qtd', 'Total', '% do Total'],
      rows,
      number_columns: [1, 2, 3]
    )

    draw_total_row('TOTAL DE DESPESAS', fmt(transactions.sum(&:amount).to_f), color: BRAND_RED)
  end

  def draw_status_summary(transactions)
    status_groups = {
      'Pago' => transactions.select { |t| t.status == 'pago' },
      'Pendente' => transactions.select { |t| t.status == 'pendente' && (t.due_date.nil? || t.due_date >= Date.today) },
      'Vencido' => transactions.select { |t| %w[pendente parcial].include?(t.status) && t.due_date && t.due_date < Date.today },
      'Cancelado' => transactions.select { |t| t.status == 'cancelado' }
    }

    rows = status_groups.filter_map do |label, txs|
      next if txs.empty?

      [label, txs.size.to_s, fmt(txs.sum(&:amount).to_f)]
    end

    draw_styled_table(['Status', 'Qtd', 'Total'], rows, number_columns: [1, 2])
  end

  def resolve_status(tx)
    return 'pago' if tx.status == 'pago'
    return 'vencido' if %w[pendente parcial].include?(tx.status) && tx.due_date && tx.due_date < Date.today

    tx.status
  end

  def status_label(status)
    { 'pago' => 'Pago', 'pendente' => 'Pendente', 'vencido' => 'Vencido',
      'parcial' => 'Parcial', 'cancelado' => 'Cancelado' }[status] || status
  end

  def truncate_text(text, max)
    text.length > max ? "#{text[0..max - 1]}..." : text
  end
end
