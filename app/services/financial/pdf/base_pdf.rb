# frozen_string_literal: true

# Base class for all financial PDF generators.
# Provides shared helpers: header, footer, currency formatting, branding, and table styling.
class Financial::Pdf::BasePdf
  BRAND_GREEN  = '16a34a'
  BRAND_RED    = 'dc2626'
  BRAND_BLUE   = '2563eb'
  BRAND_DARK   = '1e293b'
  BRAND_GRAY   = '64748b'
  BRAND_LIGHT  = 'f8fafc'
  HEADER_BG    = 'f1f5f9'
  BORDER_COLOR = 'e2e8f0'
  ROW_ALT      = 'f8fafc'

  def initialize(account:)
    @account = account
  end

  def call
    require 'prawn'
    require 'prawn/table'
    Prawn::Fonts::AFM.hide_m17n_warning = true

    @pdf = Prawn::Document.new(page_size: 'A4', margin: [40, 40, 50, 40])
    build
    stamp_page_numbers
    @pdf.render
  end

  private

  attr_reader :pdf, :account

  def build
    raise NotImplementedError, 'Subclasses must implement #build'
  end

  # ── Shared header ─────────────────────────────────────────────────────────────
  def draw_header(title:, subtitle: nil, period_label: nil)
    # Top brand bar
    pdf.fill_color BRAND_BLUE
    pdf.fill_rectangle [pdf.bounds.left - 40, pdf.cursor + 40], pdf.bounds.width + 80, 4
    pdf.fill_color BRAND_DARK

    pdf.move_down 16

    # Company name
    pdf.font_size(18) { pdf.text account.name, style: :bold, color: BRAND_DARK }
    pdf.move_down 4

    # Document title
    pdf.font_size(14) { pdf.text title.upcase, style: :bold, color: BRAND_BLUE }

    if subtitle.present?
      pdf.move_down 2
      pdf.font_size(9) { pdf.text subtitle, color: BRAND_GRAY }
    end

    if period_label.present?
      pdf.move_down 6
      draw_period_badge(period_label)
    end

    pdf.move_down 4
    pdf.stroke_color BORDER_COLOR
    pdf.stroke_horizontal_rule
    pdf.move_down 12
  end

  def draw_period_badge(label)
    pdf.fill_color 'eef2ff'
    formatted_text = "Período: #{label}"
    badge_width = pdf.width_of(formatted_text, size: 9) + 16
    pdf.fill_rounded_rectangle [0, pdf.cursor], badge_width, 18, 4
    pdf.fill_color BRAND_BLUE
    pdf.draw_text formatted_text, at: [8, pdf.cursor - 13], size: 9
    pdf.fill_color BRAND_DARK
    pdf.move_down 20
  end

  # ── KPI summary cards ─────────────────────────────────────────────────────────
  def draw_kpi_cards(cards)
    card_width = (pdf.bounds.width - ((cards.size - 1) * 12)) / cards.size
    start_x = 0

    cards.each_with_index do |card, i|
      x = start_x + (i * (card_width + 12))
      draw_single_kpi(x, card_width, card)
    end

    pdf.move_down 60
  end

  def draw_single_kpi(x, width, card)
    y = pdf.cursor
    border_color = card[:color] || BRAND_BLUE
    bg_color = card[:bg] || 'f0f9ff'

    # Card background
    pdf.fill_color bg_color
    pdf.fill_rounded_rectangle [x, y], width, 48, 4

    # Left accent bar
    pdf.fill_color border_color
    pdf.fill_rectangle [x, y], 3, 48

    # Label
    pdf.fill_color BRAND_GRAY
    pdf.draw_text card[:label].to_s.upcase, at: [x + 10, y - 16], size: 7, style: :bold

    # Value
    pdf.fill_color border_color
    pdf.draw_text card[:value].to_s, at: [x + 10, y - 34], size: 13, style: :bold

    pdf.fill_color BRAND_DARK
  end

  # ── Section title ─────────────────────────────────────────────────────────────
  def draw_section_title(title, icon: nil)
    pdf.move_down 8
    pdf.font_size(11) { pdf.text title.upcase, style: :bold, color: BRAND_DARK }
    pdf.move_down 4
    pdf.stroke_color BORDER_COLOR
    pdf.stroke_horizontal_rule
    pdf.move_down 8
  end

  # ── Styled table ──────────────────────────────────────────────────────────────
  def draw_styled_table(headers, rows, options = {})
    return draw_empty_state(options[:empty_message] || 'Nenhum dado encontrado.') if rows.empty?

    col_widths = options[:col_widths]
    num_cols   = options[:number_columns] || []

    table_data = [headers] + rows
    
    table_options = if col_widths
                      { header: true }  # col_widths controla a largura total
                    else
                      { header: true, width: pdf.bounds.width }
                    end
    table_options[:column_widths] = col_widths if col_widths

    pdf.table(table_data, **table_options) do |t|
      # Header
      t.row(0).font_style = :bold
      t.row(0).background_color = HEADER_BG
      t.row(0).text_color = BRAND_DARK
      t.row(0).size = 8

      # Body
      t.cells.padding = [6, 8, 6, 8]
      t.cells.size = 9
      t.cells.border_width = 0.5
      t.cells.border_color = BORDER_COLOR

      # Alternating row colors
      (1..rows.size).each do |i|
        t.row(i).background_color = i.odd? ? 'ffffff' : ROW_ALT
      end

      # Right-align number columns
      num_cols.each { |col| t.column(col).align = :right }
    end
  end

  # ── Total row ─────────────────────────────────────────────────────────────────
  def draw_total_row(label, value, options = {})
    color = options[:color] || BRAND_DARK
    pdf.move_down 4
    pdf.fill_color 'f0f9ff'
    pdf.fill_rounded_rectangle [0, pdf.cursor], pdf.bounds.width, 24, 3
    pdf.fill_color color
    pdf.draw_text label, at: [10, pdf.cursor - 16], size: 10, style: :bold
    pdf.draw_text value, at: [pdf.bounds.width - pdf.width_of(value, size: 11, style: :bold) - 10, pdf.cursor - 16], size: 11, style: :bold
    pdf.fill_color BRAND_DARK
    pdf.move_down 30
  end

  # ── Empty state ───────────────────────────────────────────────────────────────
  def draw_empty_state(message)
    pdf.move_down 20
    pdf.font_size(10) { pdf.text message, color: BRAND_GRAY, style: :italic, align: :center }
    pdf.move_down 20
  end

  # ── Footer / page numbers ─────────────────────────────────────────────────────
  def stamp_page_numbers
    total = pdf.page_count
    now = Time.current.in_time_zone('Brasilia').strftime('%d/%m/%Y às %H:%M')

    (1..total).each do |i|
      pdf.go_to_page(i)
      pdf.bounding_box([0, 20], width: pdf.bounds.width, height: 20) do
        pdf.stroke_color BORDER_COLOR
        pdf.stroke_horizontal_rule
        pdf.move_down 4
        pdf.font_size(7) do
          pdf.text_box "#{account.name} — Gerado em #{now}",
                       at: [0, pdf.cursor], width: pdf.bounds.width / 2, align: :left, color: BRAND_GRAY
          pdf.text_box "Página #{i} de #{total}",
                       at: [pdf.bounds.width / 2, pdf.cursor], width: pdf.bounds.width / 2, align: :right, color: BRAND_GRAY
        end
      end
    end
  end

  # ── Currency ──────────────────────────────────────────────────────────────────
  def fmt(value)
    ActionController::Base.helpers.number_to_currency(value || 0, unit: 'R$ ', separator: ',', delimiter: '.')
  end

  def fmt_date(date)
    return '—' if date.blank?

    date = Date.parse(date.to_s) unless date.is_a?(Date)
    date.strftime('%d/%m/%Y')
  rescue ArgumentError
    '—'
  end

  def fmt_pct(value)
    return '—' if value.nil?

    "#{value.round(1)}%"
  end

  def ensure_space(needed = 80)
    pdf.start_new_page if pdf.cursor < needed
  end
end
