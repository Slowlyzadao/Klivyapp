# frozen_string_literal: true

# PDF: A Receber — receivables report with configurable pagination.
class Financial::Pdf::ReceivablesPdf < Financial::Pdf::BasePdf
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
      title: 'Relatório de Contas a Receber',
      subtitle: 'Detalhamento completo dos valores a receber da sua clínica.',
      period_label: period_label
    )

    draw_kpi_cards([
      { label: 'Total a Receber', value: fmt(metrics[:total_pending]), color: BRAND_GREEN, bg: 'f0fdf4' },
      { label: 'Já Recebido',     value: fmt(metrics[:total_received]), color: BRAND_BLUE, bg: 'eff6ff' },
      { label: 'Vencido',         value: fmt(metrics[:total_overdue]),  color: BRAND_RED,  bg: 'fef2f2' },
      { label: 'Transações',      value: metrics[:count].to_s,          color: BRAND_GRAY, bg: 'f8fafc' }
    ])

    draw_section_title('Detalhamento das Transações')
    draw_transactions_table(transactions)

    ensure_space(100)
    draw_section_title('Resumo por Forma de Pagamento')
    draw_payment_method_summary(transactions)

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
    scope = account.account_transactions.kept.entradas
    scope = scope.where(due_date: @start_date..@end_date) if @start_date && @end_date

    scope = scope.includes(:patient, :financial_category)
                 .order(due_date: :asc, created_at: :desc)

    if @max_pages
      per_page = 25
      scope = scope.limit(@max_pages * per_page)
    end

    scope.to_a
  end

  def calculate_metrics(transactions)
    pending_statuses  = %w[pendente parcial]
    received_statuses = %w[recebido]

    {
      total_pending:  transactions.select { |t| pending_statuses.include?(t.status) }.sum(&:amount).to_f,
      total_received: transactions.select { |t| received_statuses.include?(t.status) }.sum(&:amount).to_f,
      total_overdue:  transactions.select { |t| pending_statuses.include?(t.status) && t.due_date && t.due_date < Date.today }.sum(&:amount).to_f,
      count: transactions.size
    }
  end

  def draw_transactions_table(transactions)
    headers = ['Paciente', 'Descrição', 'Valor', 'Vencimento', 'Recebido em', 'Forma', 'Status']

    rows = transactions.map do |tx|
      status = resolve_status(tx)
      [
        tx.patient&.name || 'Sem paciente',
        truncate_text(tx.description || '—', 30),
        fmt(tx.amount),
        fmt_date(tx.due_date),
        fmt_date(tx.received_at),
        payment_label(tx.payment_method),
        status_label(status)
      ]
    end

    draw_styled_table(headers, rows,
                      number_columns: [2],
                      col_widths: { 0 => 110, 1 => 95, 2 => 62, 3 => 58, 4 => 58, 5 => 48, 6 => 58 },
                      empty_message: 'Nenhuma transação a receber encontrada.')
  end

  def draw_payment_method_summary(transactions)
    groups = transactions.group_by(&:payment_method)
    rows = groups.map do |method, txs|
      [payment_label(method), txs.size.to_s, fmt(txs.sum(&:amount).to_f)]
    end.sort_by { |r| -r[2].gsub(/[^\d,]/, '').tr(',', '.').to_f }

    draw_styled_table(
      ['Forma de Pagamento', 'Qtd', 'Total'],
      rows,
      number_columns: [1, 2]
    )

    total = fmt(transactions.sum(&:amount).to_f)
    draw_total_row('TOTAL GERAL', total, color: BRAND_GREEN)
  end

  def draw_status_summary(transactions)
    status_groups = {
      'Recebido' => transactions.select { |t| t.status == 'recebido' },
      'Pendente' => transactions.select { |t| t.status == 'pendente' && (t.due_date.nil? || t.due_date >= Date.today) },
      'Vencido' => transactions.select { |t| %w[pendente parcial].include?(t.status) && t.due_date && t.due_date < Date.today },
      'Parcial' => transactions.select { |t| t.status == 'parcial' },
      'Cancelado' => transactions.select { |t| t.status == 'cancelado' }
    }

    rows = status_groups.map do |label, txs|
      next if txs.empty?

      [label, txs.size.to_s, fmt(txs.sum(&:amount).to_f)]
    end.compact

    draw_styled_table(['Status', 'Qtd', 'Total'], rows, number_columns: [1, 2])
  end

  # ── Helpers ─────────────────────────────────────────────────────────────────
  PAYMENT_LABELS = {
    'pix' => 'PIX', 'dinheiro' => 'Dinheiro', 'cartao_credito' => 'Crédito',
    'cartao_debito' => 'Débito', 'boleto' => 'Boleto', 'transferencia' => 'Transf.',
    'cheque' => 'Cheque'
  }.freeze

  def payment_label(method)
    PAYMENT_LABELS[method] || method || '—'
  end

  def resolve_status(tx)
    return 'recebido' if tx.status == 'recebido'
    return 'vencido' if %w[pendente parcial].include?(tx.status) && tx.due_date && tx.due_date < Date.today

    tx.status
  end

  def status_label(status)
    { 'recebido' => 'Recebido', 'pendente' => 'Pendente', 'vencido' => 'Vencido',
      'parcial' => 'Parcial', 'cancelado' => 'Cancelado' }[status] || status
  end

  def truncate_text(text, max)
    text.length > max ? "#{text[0..max - 1]}..." : text
  end
end
