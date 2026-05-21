# frozen_string_literal: true

# PDF: Fluxo de Caixa — daily cash flow report with KPI summary + daily breakdown.
class Financial::Pdf::CashFlowPdf < Financial::Pdf::BasePdf
  def initialize(account:, start_date:, end_date:)
    super(account: account)
    @start_date = start_date.to_date
    @end_date   = end_date.to_date
  end

  private

  def build
    data   = fetch_data
    totals = calculate_totals(data)

    draw_header(
      title: 'Fluxo de Caixa',
      subtitle: 'Acompanhe as entradas e saídas diárias da sua clínica.',
      period_label: "#{fmt_date(@start_date)} a #{fmt_date(@end_date)}"
    )

    draw_kpi_cards([
                     { label: 'Total de Entradas', value: fmt(totals[:entradas]), color: BRAND_GREEN, bg: 'f0fdf4' },
                     { label: 'Total de Saídas',   value: fmt(totals[:saidas]),   color: BRAND_RED,   bg: 'fef2f2' },
                     { label: 'Saldo Líquido',     value: fmt(totals[:saldo]),    color: totals[:saldo] >= 0 ? BRAND_GREEN : BRAND_RED,
                       bg: totals[:saldo] >= 0 ? 'f0fdf4' : 'fef2f2' },
                     { label: 'Saldo em Caixa',    value: fmt(totals[:saldo_acumulado]), color: BRAND_BLUE, bg: 'eff6ff' }
                   ])

    draw_section_title('Detalhamento por Dia')
    draw_daily_table(data)

    ensure_space(80)
    draw_section_title('Resumo do Período')
    draw_period_summary(data, totals)

    pdf.start_new_page
    draw_charts_page(data, totals)
  end

  def fetch_data
    Financial::CashFlowCalculator.new(
      account: account,
      start_date: @start_date,
      end_date: @end_date
    ).call
  end

  def calculate_totals(data)
    entradas = data.sum { |d| d[:entradas] }
    saidas   = data.sum { |d| d[:saidas] }
    {
      entradas: entradas,
      saidas: saidas,
      saldo: entradas - saidas,
      saldo_acumulado: data.last&.dig(:saldo_acumulado) || 0.0
    }
  end

  def draw_daily_table(data)
    headers = ['Data', 'Entradas', 'Saídas', 'Saldo do Dia', 'Saldo Acumulado']

    rows = data.map do |day|
      saldo_dia = day[:entradas] - day[:saidas]
      [
        day[:label],
        fmt(day[:entradas]),
        fmt(day[:saidas]),
        fmt(saldo_dia),
        fmt(day[:saldo_acumulado])
      ]
    end

    draw_styled_table(headers, rows,
                      number_columns: [1, 2, 3, 4],
                      empty_message: 'Nenhuma movimentação no período.')
  end

  def draw_period_summary(data, totals)
    days_with_income  = data.count { |d| d[:entradas] > 0 }
    days_with_expense = data.count { |d| d[:saidas] > 0 }
    total_days        = data.size

    avg_daily_income  = total_days > 0 ? totals[:entradas] / total_days : 0
    avg_daily_expense = total_days > 0 ? totals[:saidas] / total_days : 0

    best_day  = data.max_by { |d| d[:entradas] }
    worst_day = data.max_by { |d| d[:saidas] }

    summary_rows = [
      ['Total de dias no período', total_days.to_s],
      ['Dias com entradas', days_with_income.to_s],
      ['Dias com saídas', days_with_expense.to_s],
      ['Média diária de entradas', fmt(avg_daily_income)],
      ['Média diária de saídas', fmt(avg_daily_expense)],
      ['Melhor dia (maior entrada)', best_day ? "#{best_day[:label]} — #{fmt(best_day[:entradas])}" : '—'],
      ['Pior dia (maior saída)', worst_day ? "#{worst_day[:label]} — #{fmt(worst_day[:saidas])}" : '—']
    ]

    draw_styled_table(
      %w[Indicador Valor],
      summary_rows,
      number_columns: [1]
    )

    draw_total_row('SALDO FINAL DO PERÍODO', fmt(totals[:saldo]),
                   color: totals[:saldo] >= 0 ? BRAND_GREEN : BRAND_RED)
  end

  # ── Charts page ───────────────────────────────────────────────────────────────
  def draw_charts_page(data, _totals)
    return if data.empty?

    pdf.move_down 10
    draw_section_title('Análise Visual')

    weekly = aggregate_weekly(data)
    draw_weekly_bar_chart(weekly)

    pdf.move_down 24

    draw_balance_line_chart(data)
  end

  def aggregate_weekly(data)
    weeks = []
    current_week = { label: '', entradas: 0.0, saidas: 0.0, count: 0 }

    data.each do |day|
      current_week[:label] = day[:label] if current_week[:count].zero?
      current_week[:entradas] += day[:entradas]
      current_week[:saidas]   += day[:saidas]
      current_week[:count]    += 1

      if current_week[:count] == 7
        weeks << current_week.dup
        current_week = { label: '', entradas: 0.0, saidas: 0.0, count: 0 }
      end
    end

    weeks << current_week if current_week[:count] > 0
    weeks
  end

  def draw_legend_item(x, y, color, text)
    pdf.fill_color color
    pdf.fill_rounded_rectangle [x, y], 8, 8, 2
    pdf.fill_color BRAND_DARK
    pdf.draw_text text, at: [x + 12, y], size: 7
  end

  def draw_weekly_bar_chart(weekly)
    return if weekly.empty?

    chart_w = pdf.bounds.width
    pad_left = 55
    pad_right = 10
    legend_h = 14
    x_label_h = 14
    plot_h = 130

    max_val = [weekly.map { |w| [w[:entradas], w[:saidas]].max }.max, 1].max * 1.2

    # Legend at TOP, right after title
    legend_y = pdf.cursor - 4
    draw_legend_item(pad_left, legend_y, '16a34a', 'Entradas')
    draw_legend_item(pad_left + 65, legend_y, 'dc2626', 'Saídas')

    pdf.move_down legend_h + 6

    # Plot area
    plot_top = pdf.cursor
    plot_bottom = plot_top - plot_h
    inner_w = chart_w - pad_left - pad_right

    # Y grid lines
    5.times do |i|
      y = plot_top - (plot_h / 4.0 * i)
      val = max_val / 4.0 * (4 - i)
      pdf.stroke_color BORDER_COLOR
      pdf.stroke_horizontal_line pad_left, chart_w - pad_right, at: y
      if i < 5
        pdf.fill_color BRAND_GRAY
        pdf.draw_text format_short(val), at: [0, y - 4], size: 7
      end
    end

    # X axis baseline
    pdf.stroke_color 'cbd5e1'
    pdf.stroke_horizontal_line pad_left, chart_w - pad_right, at: plot_bottom

    # Bars
    bar_group_w = inner_w.to_f / [weekly.size, 1].max
    bar_w = [bar_group_w * 0.3, 4].max
    bar_gap = 2

    weekly.each_with_index do |w, i|
      group_x = pad_left + (i * bar_group_w) + ((bar_group_w - ((bar_w * 2) + bar_gap)) / 2)

      # Entrada bar — Prawn fill_rounded_rectangle draws DOWN from y, so top = plot_bottom + height
      e_h = w[:entradas] > 0 ? (w[:entradas] / max_val * plot_h) : 0
      if e_h > 0
        pdf.fill_color '16a34a'
        pdf.fill_rounded_rectangle [group_x, plot_bottom + e_h], bar_w, e_h, 2
      end

      # Saída bar
      s_h = w[:saidas] > 0 ? (w[:saidas] / max_val * plot_h) : 0
      if s_h > 0
        pdf.fill_color 'dc2626'
        pdf.fill_rounded_rectangle [group_x + bar_w + bar_gap, plot_bottom + s_h], bar_w, s_h, 2
      end

      # X label below baseline
      pdf.fill_color BRAND_GRAY
      center_x = group_x + bar_w + (bar_gap / 2)
      label_w = pdf.width_of(w[:label], size: 6)
      pdf.draw_text w[:label], at: [center_x - (label_w / 2), plot_bottom - 12], size: 6
    end

    pdf.fill_color BRAND_DARK
    pdf.move_down plot_h + x_label_h + 8
  end

  def draw_balance_line_chart(data)
    return if data.size < 2

    chart_w = pdf.bounds.width
    pad_left = 55
    pad_right = 10
    legend_h = 14
    x_label_h = 14
    plot_h = 130
    inner_w = chart_w - pad_left - pad_right

    balances = data.map { |d| d[:saldo_acumulado] }
    min_val = balances.min
    max_val = balances.max
    range = [max_val - min_val, 1].max

    # Legend at TOP
    legend_y = pdf.cursor - 4
    draw_legend_item(pad_left, legend_y, '2563eb', 'Saldo Acumulado')

    pdf.move_down legend_h + 6

    # Plot area
    plot_top = pdf.cursor
    plot_bottom = plot_top - plot_h

    # Y grid
    5.times do |i|
      y = plot_top - (plot_h / 4.0 * i)
      val = min_val + (range / 4.0 * (4 - i))
      pdf.stroke_color BORDER_COLOR
      pdf.stroke_horizontal_line pad_left, chart_w - pad_right, at: y
      pdf.fill_color BRAND_GRAY
      pdf.draw_text format_short(val), at: [0, y - 4], size: 7
    end

    # X axis baseline
    pdf.stroke_color 'cbd5e1'
    pdf.stroke_horizontal_line pad_left, chart_w - pad_right, at: plot_bottom

    # Build points — ratio 0 = plot_bottom (min value), ratio 1 = plot_top (max value)
    points = data.map.with_index do |d, i|
      x = pad_left + (data.size > 1 ? (i.to_f / (data.size - 1)) * inner_w : inner_w / 2)
      ratio = (d[:saldo_acumulado] - min_val) / range
      y = plot_bottom + (ratio * plot_h)
      [x, y]
    end

    # Area fill — light blue so grid remains visible
    if points.size >= 2
      area_path = "M #{points.first[0]},#{plot_bottom}"
      points.each { |p| area_path += " L #{p[0]},#{p[1]}" }
      area_path += " L #{points.last[0]},#{plot_bottom} Z"
      pdf.fill_color 'bfdbfe'
      pdf.fill_polygon(*parse_polygon_points(area_path))
    end

    # Line on top of area
    if points.size >= 2
      (0...points.size - 1).each do |i|
        pdf.stroke_color '2563eb'
        pdf.line_width 2
        pdf.stroke_line(points[i], points[i + 1])
      end
    end

    # Dots on top of line
    points.each do |px, py|
      pdf.fill_color '2563eb'
      pdf.fill_circle [px, py], 3
      pdf.fill_color 'ffffff'
      pdf.fill_circle [px, py], 1.5
    end

    # X labels (sparse)
    pdf.fill_color BRAND_GRAY
    step = [1, (data.size / 8.0).ceil].max
    data.each_with_index do |d, idx|
      next unless (idx % step).zero? || idx == data.size - 1

      x = pad_left + (data.size > 1 ? (idx.to_f / (data.size - 1)) * inner_w : inner_w / 2)
      pdf.draw_text d[:label], at: [x - 8, plot_bottom - 12], size: 6
    end

    pdf.fill_color BRAND_DARK
    pdf.move_down plot_h + x_label_h + 8
  end

  def format_short(val)
    n = val.to_f
    if n.abs >= 1_000_000
      "R$ #{(n / 1_000_000).round(1)}M"
    elsif n.abs >= 1_000
      "R$ #{(n / 1_000).round(1)}k"
    else
      "R$ #{n.round(0)}"
    end
  end

  def parse_polygon_points(path)
    coords = path.scan(/-?[\d.]+/).map(&:to_f)
    coords.each_slice(2).to_a
  end
end
