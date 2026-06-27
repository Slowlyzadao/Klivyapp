# frozen_string_literal: true

# Superclass abstrata para todos os geradores de PDF do plugin Patients.
# Concentra tokens visuais, header/footer repetidos e componentes (section
# title, key-value grid, badge, tabela, total row, assinaturas, bullets).
#
# Subclasses sobrescrevem `#build` para desenhar o conteúdo. Identificação
# da clínica vem de `account.name`; brand do produto (footer legal) vem de
# `BRAND_NAME` via `GlobalConfigService`.
module Patients
  module Pdf
    class BasePdf
      PRIMARY        = '2563EB'
      PRIMARY_DARK   = '1E40AF'
      SUCCESS        = '16A34A'
      SUCCESS_LIGHT  = 'D1FAE5'
      SUCCESS_DARK   = '065F46'
      WARNING_LIGHT  = 'FEF3C7'
      WARNING_DARK   = '92400E'
      DANGER         = 'DC2626'
      DANGER_LIGHT   = 'FEE2E2'
      DANGER_DARK    = '991B1B'
      INFO_LIGHT     = 'EFF6FF'
      INFO_DARK      = '1E40AF'
      TEXT_PRIMARY   = '0F172A'
      TEXT_SECONDARY = '475569'
      TEXT_MUTED     = '94A3B8'
      DIVIDER        = 'E2E8F0'
      BG_LIGHT       = 'F8FAFC'
      HEADER_BG      = 'F1F5F9'
      WHITE          = 'FFFFFF'
      BLACK          = '000000'

      PAGE_MARGIN_X   = 50
      PAGE_MARGIN_TOP = 85
      PAGE_MARGIN_BOTTOM = 50

      def self.call(**args)
        new(**args).call
      end

      def call
        require 'prawn'
        require 'prawn/table'
        ::Prawn::Fonts::AFM.hide_m17n_warning = true

        @pdf = ::Prawn::Document.new(
          page_size: 'A4',
          margin: [PAGE_MARGIN_TOP, PAGE_MARGIN_X, PAGE_MARGIN_BOTTOM, PAGE_MARGIN_X]
        )
        @pdf.default_leading 1
        draw_repeating_chrome
        build
        @pdf.render
      end

      private

      attr_reader :pdf

      def build
        raise NotImplementedError, "#{self.class} must implement #build"
      end

      # Subclasses sobrescrevem para fornecer dados ao header/footer.
      def header_account_name
        ''
      end

      def header_subtitle
        ''
      end

      def header_initial
        (header_account_name.to_s.strip[0] || 'K').upcase
      end

      def footer_document_id
        nil
      end

      def brand_name
        @brand_name ||= begin
          value = ::GlobalConfigService.load('BRAND_NAME', 'Klivy').to_s.strip
          value.presence || 'Klivy'
        end
      end

      def formatted_now
        Time.current.in_time_zone('Brasilia').strftime('%d/%m/%Y %H:%M')
      end

      # ── Chrome (header + footer repetidos em todas as páginas) ─────────
      def draw_repeating_chrome
        pdf.repeat(:all) do
          draw_header_band
          draw_footer_band
        end
      end

      def draw_header_band
        pdf.canvas do
          pdf.fill_color PRIMARY_DARK
          pdf.fill_rectangle [0, pdf.bounds.top], pdf.bounds.width, 60
          pdf.fill_color PRIMARY
          pdf.fill_rectangle [0, pdf.bounds.top - 60], pdf.bounds.width, 3

          pdf.fill_color WHITE
          pdf.fill_rounded_rectangle [PAGE_MARGIN_X, pdf.bounds.top - 18], 28, 28, 5
          pdf.fill_color PRIMARY_DARK
          pdf.font('Helvetica', style: :bold) do
            pdf.text_box(
              header_initial,
              at: [PAGE_MARGIN_X, pdf.bounds.top - 22],
              width: 28, height: 22, size: 14,
              align: :center, valign: :center,
              overflow: :truncate
            )
          end

          pdf.fill_color WHITE
          pdf.font('Helvetica', style: :bold) do
            pdf.text_box(
              header_account_name.to_s,
              at: [PAGE_MARGIN_X + 40, pdf.bounds.top - 20],
              width: pdf.bounds.width - PAGE_MARGIN_X - 50, height: 18, size: 13,
              overflow: :truncate
            )
          end
          pdf.font('Helvetica') do
            pdf.text_box(
              header_subtitle.to_s,
              at: [PAGE_MARGIN_X + 40, pdf.bounds.top - 38],
              width: pdf.bounds.width - PAGE_MARGIN_X - 50, height: 12, size: 8.5,
              overflow: :truncate
            )
          end

          pdf.fill_color TEXT_PRIMARY
        end
      end

      def draw_footer_band
        pdf.canvas do
          pdf.stroke_color DIVIDER
          pdf.line_width 0.5
          pdf.stroke_horizontal_line PAGE_MARGIN_X, pdf.bounds.width - PAGE_MARGIN_X, at: 32

          pdf.fill_color TEXT_MUTED
          pdf.font('Helvetica') do
            pdf.text_box(
              footer_left_text,
              at: [PAGE_MARGIN_X, 22],
              width: pdf.bounds.width - 2 * PAGE_MARGIN_X - 80, height: 10, size: 7.5,
              overflow: :truncate
            )
            pdf.text_box(
              "Página #{pdf.page_number}",
              at: [pdf.bounds.width - PAGE_MARGIN_X - 80, 22],
              width: 80, height: 10, size: 7.5,
              align: :right
            )
          end
          pdf.fill_color TEXT_PRIMARY
          pdf.stroke_color BLACK
        end
      end

      def footer_left_text
        parts = []
        parts << "Documento ##{footer_document_id}" if footer_document_id.present?
        parts << "gerado por #{brand_name}"
        parts << "em #{formatted_now}"
        parts.join(' · ')
      end

      # ── Section title (banda lateral colorida + título uppercase) ──────
      def draw_section_title(title)
        ensure_space(50)
        pdf.fill_color PRIMARY
        pdf.fill_rectangle [0, pdf.cursor], 3, 14
        pdf.fill_color TEXT_PRIMARY
        pdf.font('Helvetica', style: :bold) do
          pdf.text_box(
            title.to_s.upcase,
            at: [10, pdf.cursor - 3], width: pdf.bounds.width - 20,
            size: 10, character_spacing: 0.6, height: 12
          )
        end
        pdf.move_down 16

        pdf.stroke_color DIVIDER
        pdf.line_width 0.5
        pdf.stroke_horizontal_line 0, pdf.bounds.width
        pdf.stroke_color BLACK
        pdf.move_down 6
      end

      def draw_subsection(label)
        ensure_space(40)
        pdf.fill_color PRIMARY_DARK
        pdf.font('Helvetica', style: :bold) { pdf.text label.to_s, size: 9 }
        pdf.fill_color TEXT_PRIMARY
        pdf.move_down 2

        yield

        pdf.move_down 7
      end

      # ── Key/value grid (rows label-uppercase + value-bold em N colunas) ─
      def draw_kv_grid(rows, columns: 2)
        pdf.font('Helvetica') do
          rows.each_slice(columns) do |slice|
            ensure_space(36)
            col_width = (pdf.bounds.width - (columns - 1) * 10) / columns
            start_y = pdf.cursor

            slice.each_with_index do |(label, value), i|
              x = i * (col_width + 10)
              pdf.fill_color TEXT_MUTED
              pdf.text_box(label.to_s.upcase, at: [x, start_y], width: col_width, size: 7, character_spacing: 0.5, height: 9)
              pdf.fill_color TEXT_PRIMARY
              pdf.font('Helvetica', style: :bold) do
                pdf.text_box(value.to_s, at: [x, start_y - 11], width: col_width, size: 10, height: 13, overflow: :truncate)
              end
            end

            pdf.move_down 26
          end
        end
      end

      # ── Highlighted block (caixa destacada com label + corpo) ──────────
      def draw_highlight_block(label:, content:, color: PRIMARY)
        body = content.to_s
        body = body.presence || '—'
        content_height = pdf.height_of(body, width: pdf.bounds.width - 24, size: 10)
        box_height = [30, content_height + 22].max
        ensure_space(box_height + 10)

        pdf.fill_color BG_LIGHT
        pdf.fill_rectangle [0, pdf.cursor], pdf.bounds.width, box_height
        pdf.fill_color color
        pdf.fill_rectangle [0, pdf.cursor], 3, box_height

        pdf.fill_color TEXT_MUTED
        pdf.text_box(label.to_s.upcase, at: [12, pdf.cursor - 6], width: pdf.bounds.width - 24, size: 7, character_spacing: 0.5, height: 9)
        pdf.fill_color TEXT_PRIMARY
        pdf.font('Helvetica', style: :italic) do
          pdf.text_box(
            body,
            at: [12, pdf.cursor - 18],
            width: pdf.bounds.width - 24, height: content_height,
            size: 10, overflow: :shrink_to_fit, min_font_size: 8.5
          )
        end

        pdf.fill_color TEXT_PRIMARY
        pdf.move_down(box_height + 10)
      end

      # ── Bullet ─────────────────────────────────────────────────────────
      def draw_bullet(text, muted: false)
        bullet_y = pdf.cursor - 4
        pdf.fill_color muted ? TEXT_MUTED : PRIMARY
        pdf.fill_circle [4, bullet_y], 1.4
        pdf.fill_color muted ? TEXT_MUTED : TEXT_SECONDARY
        pdf.font('Helvetica') do
          pdf.indent(12) { pdf.text text.to_s, size: 9 }
        end
        pdf.fill_color TEXT_PRIMARY
      end

      # ── Inline badge (intent: :success/:danger/:warning/:info) ─────────
      def badge_palette(intent)
        case intent
        when :success then { bg: SUCCESS_LIGHT, fg: SUCCESS_DARK }
        when :danger  then { bg: DANGER_LIGHT,  fg: DANGER_DARK  }
        when :warning then { bg: WARNING_LIGHT, fg: WARNING_DARK }
        else               { bg: INFO_LIGHT,    fg: INFO_DARK    }
        end
      end

      def draw_centered_badge(text, intent: :info)
        colors = badge_palette(intent)
        text_width = pdf.width_of(text.to_s, size: 9, style: :bold)
        width = text_width + 24
        x = (pdf.bounds.width - width) / 2
        y = pdf.cursor

        pdf.fill_color colors[:bg]
        pdf.fill_rounded_rectangle [x, y], width, 18, 9
        pdf.fill_color colors[:fg]
        pdf.font('Helvetica', style: :bold) do
          pdf.text_box(
            text.to_s.upcase,
            at: [x, y - 4],
            width: width, height: 12,
            size: 9, character_spacing: 0.5,
            align: :center
          )
        end
        pdf.fill_color TEXT_PRIMARY
        pdf.move_down 22
      end

      # ── Data table (header cinza + zebra + alinhamento numérico) ───────
      def draw_data_table(headers, rows, number_columns: [], col_widths: nil, empty_message: 'Sem dados.')
        return draw_empty(empty_message) if rows.blank?

        ensure_space(60)

        opts = if col_widths
                 { header: true, column_widths: col_widths }
               else
                 { header: true, width: pdf.bounds.width }
               end

        pdf.table([headers] + rows, **opts) do |t|
          t.row(0).font_style = :bold
          t.row(0).background_color = HEADER_BG
          t.row(0).text_color = TEXT_PRIMARY
          t.row(0).size = 9
          t.cells.padding = [6, 8, 6, 8]
          t.cells.size = 9
          t.cells.border_width = 0.5
          t.cells.border_color = DIVIDER
          (1..rows.size).each do |i|
            t.row(i).background_color = i.odd? ? WHITE : BG_LIGHT
          end
          number_columns.each { |col| t.column(col).align = :right }
        end
      end

      # ── Total row (caixa destacada com label esq + valor dir) ──────────
      def draw_total_row(label, value, color: PRIMARY_DARK)
        ensure_space(40)
        pdf.move_down 4
        pdf.fill_color BG_LIGHT
        pdf.fill_rounded_rectangle [0, pdf.cursor], pdf.bounds.width, 24, 3
        pdf.fill_color color
        pdf.draw_text label.to_s, at: [10, pdf.cursor - 16], size: 10, style: :bold
        val_width = pdf.width_of(value.to_s, size: 11, style: :bold)
        pdf.draw_text value.to_s, at: [pdf.bounds.width - val_width - 10, pdf.cursor - 16], size: 11, style: :bold
        pdf.fill_color TEXT_PRIMARY
        pdf.move_down 30
      end

      # ── Empty state ────────────────────────────────────────────────────
      def draw_empty(message)
        pdf.move_down 6
        pdf.fill_color TEXT_MUTED
        pdf.font('Helvetica', style: :italic) { pdf.text message.to_s, size: 9, align: :center }
        pdf.fill_color TEXT_PRIMARY
        pdf.move_down 6
      end

      # ── Signatures (1 ou 2 colunas paralelas com linha + nome + caption) ─
      # `left` e `right` são Hashes: { name:, caption:, caption_italic: }
      def draw_signatures(left:, right: nil)
        ensure_space(80)
        pdf.move_down 22
        sig_y = pdf.cursor

        if right
          col_width = (pdf.bounds.width - 40) / 2
          pdf.stroke_color DIVIDER
          pdf.line_width 0.7
          pdf.stroke_horizontal_line 0, col_width, at: sig_y
          pdf.stroke_horizontal_line col_width + 40, pdf.bounds.width, at: sig_y
          pdf.stroke_color BLACK

          draw_signature_label(left,  x: 0,                  width: col_width, y: sig_y)
          draw_signature_label(right, x: col_width + 40,     width: col_width, y: sig_y)
        else
          col_width = pdf.bounds.width / 2
          x = (pdf.bounds.width - col_width) / 2
          pdf.stroke_color DIVIDER
          pdf.line_width 0.7
          pdf.stroke_horizontal_line x, x + col_width, at: sig_y
          pdf.stroke_color BLACK

          draw_signature_label(left, x: x, width: col_width, y: sig_y)
        end

        pdf.move_down 36
      end

      def draw_signature_label(sig, x:, width:, y:)
        pdf.fill_color TEXT_PRIMARY
        pdf.font('Helvetica', style: :bold) do
          pdf.text_box(sig[:name].to_s, at: [x, y - 4], width: width, size: 10, height: 13, align: :center)
        end
        pdf.fill_color TEXT_MUTED
        pdf.font('Helvetica', style: sig[:caption_italic] ? :italic : :normal) do
          pdf.text_box(sig[:caption].to_s, at: [x, y - 18], width: width, size: 7.5, height: 10, align: :center)
        end
        pdf.fill_color TEXT_PRIMARY
      end

      # ── Quebra de página adaptativa ────────────────────────────────────
      def ensure_space(needed = 80)
        pdf.start_new_page if pdf.cursor < needed
      end

      # ── Formatters ─────────────────────────────────────────────────────
      def fmt_currency(value)
        ::ActionController::Base.helpers.number_to_currency(value || 0, unit: 'R$ ', separator: ',', delimiter: '.')
      end

      def fmt_date(date)
        return '—' if date.blank?

        d = date.is_a?(::Date) || date.is_a?(::Time) || date.is_a?(::DateTime) ? date : ::Date.parse(date.to_s)
        d.strftime('%d/%m/%Y')
      rescue ::ArgumentError, ::TypeError
        '—'
      end

      def fmt_datetime(time)
        return '—' if time.blank?

        time.in_time_zone('Brasilia').strftime('%d/%m/%Y às %H:%M')
      end

      def fmt_cpf(cpf)
        return 'Não informado' if cpf.blank?

        digits = cpf.to_s.gsub(/\D/, '')
        return cpf.to_s unless digits.length == 11

        "#{digits[0..2]}.#{digits[3..5]}.#{digits[6..8]}-#{digits[9..10]}"
      end
    end
  end
end
