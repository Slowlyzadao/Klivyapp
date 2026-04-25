# frozen_string_literal: true

module Patients
  class TreatmentPlanPdfGenerator
    def self.call(**args)
      new(**args).call
    end

    def initialize(treatment_plan:, actor: nil)
      @treatment_plan = treatment_plan
      @patient = treatment_plan.patient
      @account = treatment_plan.account
      @actor = actor || treatment_plan.approved_by || treatment_plan.professional
    end

    def call
      pdf_data = generate_pdf

      # Attach the generated PDF directly to the TreatmentPlan
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

    def generate_pdf
      require 'prawn'
      require 'prawn/table'
      Prawn::Fonts::AFM.hide_m17n_warning = true

      pdf = Prawn::Document.new(page_size: 'A4', margin: [50, 50, 60, 50])

      draw_header(pdf)
      draw_patient_data(pdf)
      draw_plan_details(pdf)
      draw_items_table(pdf)
      draw_footer(pdf)

      pdf.render
    end

    def draw_header(pdf)
      pdf.font_size(20) { pdf.text account.name, style: :bold, align: :center }
      pdf.move_down 10
      pdf.font_size(14) { pdf.text 'PLANO DE TRATAMENTO', style: :bold, align: :center }
      pdf.move_down 5

      status_text = treatment_plan.status.to_s.humanize
      pdf.font_size(10) { pdf.text "Status: #{status_text.upcase}", align: :center, style: :bold }
      pdf.move_down 30
    end

    def draw_patient_data(pdf)
      pdf.font_size(12) { pdf.text 'DADOS DO PACIENTE', style: :bold }
      pdf.move_down 5
      pdf.font_size(10) do
        pdf.text "Nome: #{patient.name}"
        pdf.text "CPF: #{format_cpf(patient.cpf)} | Data de Nascimento: #{patient.birthdate&.strftime('%d/%m/%Y') || 'Não informada'}"

        address = format_address(patient.address)
        pdf.text "Endereço: #{address}" if address.present?
      end
      pdf.move_down 20
    end

    def draw_plan_details(pdf)
      pdf.font_size(12) { pdf.text 'DIAGNÓSTICO E HIPÓTESE', style: :bold }
      pdf.move_down 5
      pdf.font_size(10) do
        pdf.text "Justificativa Clínica / Queixa Principal: #{treatment_plan.description.presence || 'Nenhuma informada'}"
        pdf.text "Hipótese Diagnóstica / CID: #{treatment_plan.title.presence || 'Nenhum informado'}"
      end
      pdf.move_down 20
    end

    def draw_items_table(pdf)
      pdf.font_size(12) { pdf.text 'PROCEDIMENTOS PLANEJADOS', style: :bold }
      pdf.move_down 10

      items = treatment_plan.treatment_items
      if items.empty?
        pdf.font_size(10) { pdf.text 'Nenhum procedimento cadastrado neste plano.', style: :italic }
        return
      end

      table_data = [['Procedimento', 'Região/Elemento', 'Sessões', 'Valor Un.', 'Subtotal', 'Status']]

      total_estimado = 0

      items.each do |item|
        total_estimado += item.total_price.to_f
        table_data << [
          item.procedure_name || '-',
          item.region || '-',
          item.sessions_planned.to_s,
          format_currency(item.unit_price),
          format_currency(item.total_price),
          item.status.to_s.humanize.upcase
        ]
      end

      pdf.table(table_data, header: true, width: pdf.bounds.width) do
        row(0).font_style = :bold
        row(0).background_color = 'EEEEEE'
        row(0).align = :center
        column(2).align = :center
        column(3).align = :right
        column(4).align = :right
        column(5).align = :center
        cells.padding = 6
        cells.size = 10
      end

      pdf.move_down 10
      pdf.font_size(11) do
        pdf.text "TOTAL ESTIMADO: #{format_currency(total_estimado)}", style: :bold, align: :right
      end
    end

    def draw_footer(pdf)
      pdf.move_down 50

      pdf.font_size(10) do
        if treatment_plan.approved_at
          pdf.text "Plano aprovado em #{treatment_plan.approved_at.strftime('%d/%m/%Y')}.", align: :center
        else
          pdf.text 'Plano pendente de aprovação.', align: :center
        end
      end

      pdf.move_down 40
      pdf.stroke_horizontal_rule
      pdf.move_down 5
      pdf.text "Assinatura do Paciente: #{patient.name}", align: :center, size: 10

      pdf.move_down 40
      pdf.stroke_horizontal_rule
      pdf.move_down 5
      professional_name = actor&.name || 'Profissional Responsável'
      pdf.text "Assinado eletronicamente por #{professional_name}", align: :center, size: 10

      time = Time.current
      pdf.text "Data/Hora: #{time.in_time_zone('Brasilia').strftime('%d/%m/%Y às %H:%M')}", align: :center, size: 10
    end

    def format_currency(value)
      ActionController::Base.helpers.number_to_currency(value, unit: 'R$ ', separator: ',', delimiter: '.')
    end

    def format_cpf(cpf)
      return 'Não informado' if cpf.blank?

      clean_cpf = cpf.to_s.gsub(/\D/, '')
      if clean_cpf.length == 11
        "#{clean_cpf[0..2]}.#{clean_cpf[3..5]}.#{clean_cpf[6..8]}-#{clean_cpf[9..10]}"
      else
        cpf # fallback if it's malformed
      end
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
