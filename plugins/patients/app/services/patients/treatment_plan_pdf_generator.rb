# frozen_string_literal: true

module Patients
  class TreatmentPlanPdfGenerator < Patients::Pdf::BasePdf
    STATUS_INTENT = {
      'aprovado' => :success,
      'cancelado' => :danger,
      'pendente' => :warning,
      'rascunho' => :info,
      'concluido' => :success
    }.freeze

    def initialize(treatment_plan:, actor: nil)
      @treatment_plan = treatment_plan
      @patient        = treatment_plan.patient
      @account        = treatment_plan.account
      @actor          = actor || treatment_plan.approved_by || treatment_plan.professional
    end

    def call
      pdf_data = super

      @treatment_plan.pdf.attach(
        io: StringIO.new(pdf_data),
        filename: "plano_tratamento_#{@patient.name.parameterize}_#{@treatment_plan.id}.pdf",
        content_type: 'application/pdf'
      )

      true
    rescue StandardError => e
      Rails.logger.error("[TreatmentPlanPdfGenerator] Erro ao gerar/anexar PDF: #{e.message}")
      false
    end

    private

    attr_reader :treatment_plan, :patient, :account, :actor

    def header_account_name
      account&.name.to_s
    end

    def header_subtitle
      'Plano de Tratamento'
    end

    def footer_document_id
      treatment_plan.id.to_s
    end

    def build
      draw_status_badge
      draw_patient_card
      draw_items_table
      draw_total
      draw_signatures_block
    end

    def draw_status_badge
      status = treatment_plan.status.to_s
      intent = STATUS_INTENT[status] || :info
      draw_centered_badge("Status: #{status.humanize}", intent: intent)
    end

    def draw_patient_card
      draw_section_title('Dados do Paciente')

      draw_kv_grid(
        [
          ['Nome', patient.name.to_s],
          ['CPF', fmt_cpf(patient.cpf)],
          ['Data de Nascimento', patient.birthdate&.strftime('%d/%m/%Y') || 'Não informada']
        ]
      )

      address = format_address(patient.address)
      draw_highlight_block(label: 'Endereço', content: address) if address.present?
    end

    def draw_items_table
      draw_section_title('Procedimentos Planejados')

      items = treatment_plan.treatment_items
      headers = ['Procedimento', 'Região/Elemento', 'Sessões', 'Valor Un.', 'Desconto', 'Subtotal']
      rows = items.map do |item|
        discount = item.respond_to?(:discount_amount) ? item.discount_amount.to_f : 0.0
        [
          item.procedure_name || '—',
          item.region.presence || '—',
          item.sessions_planned.to_s,
          fmt_currency(item.unit_price),
          discount.positive? ? "- #{fmt_currency(discount)}" : '—',
          fmt_currency(item.total_price)
        ]
      end

      draw_data_table(
        headers, rows,
        number_columns: [3, 4, 5],
        empty_message: 'Nenhum procedimento cadastrado neste plano.'
      )
    end

    def draw_total
      total = treatment_plan.treatment_items.sum { |i| i.total_price.to_f }
      return if total.zero? && treatment_plan.treatment_items.empty?

      draw_total_row('TOTAL ESTIMADO', fmt_currency(total), color: SUCCESS_DARK)
    end

    def draw_signatures_block
      pdf.move_down 8
      pdf.fill_color TEXT_SECONDARY
      pdf.font('Helvetica', style: :italic) do
        approved_text = if treatment_plan.approved_at
                          "Plano aprovado em #{fmt_date(treatment_plan.approved_at)}."
                        else
                          'Plano pendente de aprovação.'
                        end
        pdf.text approved_text, align: :center, size: 8.5
      end
      pdf.fill_color TEXT_PRIMARY

      professional_name = actor&.name || 'Profissional Responsável'

      draw_signatures(
        left: {
          name: patient.name,
          caption: 'Assinatura do Paciente'
        },
        right: {
          name: professional_name,
          caption: "Assinado eletronicamente em #{fmt_datetime(Time.current)}",
          caption_italic: true
        }
      )
    end

    def format_address(address)
      return nil if address.blank? || !address.is_a?(Hash)

      parts = []
      parts << "#{address['street']}, #{address['number'].presence || 'S/N'}" if address['street'].present?
      parts << address['complement'] if address['complement'].present?
      parts << "- #{address['neighborhood']}" if address['neighborhood'].present?
      parts << "- #{address['city']}/#{address['state']}" if address['city'].present?
      parts << "| CEP: #{address['zip_code']}" if address['zip_code'].present?

      parts.join(' ')
    end
  end
end
