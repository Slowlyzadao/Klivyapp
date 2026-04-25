# frozen_string_literal: true

# app/services/patients/pdf_generator.rb
#
# Serviço de geração de PDFs com Prawn.
# Recebe um paciente, um tipo de documento e variáveis, gera o PDF e
# retorna um Result struct com o file_data (binário) e metadados.
#
# Uso:
#   result = Patients::PdfGenerator.call(
#     patient: @patient,
#     document_type: 'atestado',
#     variables: { cid: 'Z03.0', duration_days: 2, professional_name: 'Dr. João' },
#     generated_by: current_user
#   )
#   if result.success?
#     result.pdf_data   # Binário do PDF
#     result.document   # Instância de Document salvo
#   end

module Patients
  class PdfGenerator
    Result = Struct.new(:success?, :document, :pdf_data, :error, keyword_init: true)

    def self.call(**args)
      new(**args).call
    end

    def initialize(patient:, document_type:, variables: {}, generated_by: nil, title: nil, form_template_id: nil)
      @patient         = patient
      @document_type   = document_type
      @variables       = variables
      @generated_by    = generated_by
      @title           = title || default_title(document_type)
      @form_template_id = form_template_id
    end

    def call
      pdf_data = generate_pdf

      document = save_document(pdf_data)

      Result.new(success?: true, document: document, pdf_data: pdf_data, error: nil)
    rescue StandardError => e
      Rails.logger.error("[PdfGenerator] Erro ao gerar PDF: #{e.message}")
      Result.new(success?: false, document: nil, pdf_data: nil, error: e.message)
    end

    private

    attr_reader :patient, :document_type, :variables, :generated_by, :title, :form_template_id

    def generate_pdf
      require 'prawn'

      pdf = Prawn::Document.new(
        page_size: 'A4',
        margin: [60, 60, 60, 60]
      )

      # Cabeçalho da clínica
      draw_header(pdf)

      # Título do documento
      draw_document_title(pdf)

      # Identificação do paciente
      draw_patient_info(pdf)

      # Conteúdo específico por tipo de documento
      case document_type
      when 'atestado'
        draw_atestado(pdf)
      when 'receita'
        draw_receita(pdf)
      when 'pedido_exame'
        draw_pedido_exame(pdf)
      when 'declaracao'
        draw_declaracao(pdf)
      when 'relatorio_clinico'
        draw_relatorio_clinico(pdf)
      when 'encaminhamento'
        draw_encaminhamento(pdf)
      else
        draw_generic(pdf)
      end

      # Rodapé com assinatura
      draw_footer(pdf)

      pdf.render
    end

    def draw_header(pdf)
      account_name = begin
        patient.account.name
      rescue StandardError
        'BeClinic'
      end

      pdf.font_size(18) { pdf.text account_name, style: :bold, align: :center }
      pdf.move_down 4
      pdf.stroke_horizontal_rule
      pdf.move_down 16
    end

    def draw_document_title(pdf)
      pdf.font_size(14) do
        pdf.text title.upcase, style: :bold, align: :center
      end
      pdf.move_down 20
    end

    def draw_patient_info(pdf)
      pdf.font_size(10) do
        pdf.text "Paciente: #{patient.name}", style: :bold
        pdf.text "CPF: #{patient.cpf.presence || '—'}"
        pdf.text "Data de Nascimento: #{patient.birthdate&.strftime('%d/%m/%Y') || '—'}"
        pdf.text "Data: #{Date.today.strftime('%d/%m/%Y')}"
      end
      pdf.stroke_horizontal_rule
      pdf.move_down 16
    end

    def draw_atestado(pdf)
      duration_days = variables['duration_days'] || variables[:duration_days]
      cid           = variables['cid'] || variables[:cid]
      reason        = variables['reason'] || variables[:reason] || 'Para os devidos fins'
      professional  = variables['professional_name'] || variables[:professional_name] || (generated_by&.name || '—')

      pdf.font_size(11) do
        pdf.text 'Atesto que o(a) paciente acima identificado(a) encontra-se sob meus cuidados ' \
                 'profissionais, necessitando de afastamento de suas atividades por um período de ' \
                 "#{duration_days || '___'} (#{days_in_full(duration_days)}) dia(s) a partir desta data.", inline_format: true
        pdf.move_down 10

        if cid.present?
          pdf.text "CID-10: #{cid}"
          pdf.move_down 8
        end

        pdf.text reason.to_s
        pdf.move_down 30

        pdf.text '___________________________________'
        pdf.text professional.to_s
        pdf.text "CRM/CRO/CRF: #{variables['crm'] || variables[:crm] || '___________'}"
      end
    end

    def draw_receita(pdf)
      medications = variables['medications'] || variables[:medications] || []
      professional = variables['professional_name'] || variables[:professional_name] || (generated_by&.name || '—')

      pdf.font_size(11) do
        pdf.text 'RECEITA MÉDICA', style: :bold, align: :center
        pdf.move_down 12

        if medications.any?
          medications.each_with_index do |med, idx|
            pdf.text "#{idx + 1}. #{med['name'] || med[:name]}", style: :bold
            pdf.text "   #{med['dosage'] || med[:dosage]}" if (med['dosage'] || med[:dosage]).present?
            pdf.text "   #{med['instructions'] || med[:instructions]}" if (med['instructions'] || med[:instructions]).present?
            pdf.move_down 8
          end
        else
          pdf.text '_____________________________________________'
          pdf.move_down 60
        end

        pdf.move_down 20
        pdf.text '___________________________________'
        pdf.text professional.to_s
      end
    end

    def draw_pedido_exame(pdf)
      exams = variables['exams'] || variables[:exams] || []
      indication = variables['clinical_indication'] || variables[:clinical_indication]
      professional = variables['professional_name'] || variables[:professional_name] || (generated_by&.name || '—')

      pdf.font_size(11) do
        pdf.text 'PEDIDO DE EXAME', style: :bold, align: :center
        pdf.move_down 12

        if indication.present?
          pdf.text "Indicação Clínica: #{indication}", style: :italic
          pdf.move_down 8
        end

        pdf.text 'Solicito os seguintes exames:', style: :bold
        pdf.move_down 8

        if exams.any?
          exams.each do |exam|
            pdf.text "• #{exam}"
          end
        else
          pdf.text '_____________________________________________'
          pdf.move_down 40
        end

        pdf.move_down 20
        pdf.text '___________________________________'
        pdf.text professional.to_s
      end
    end

    def draw_encaminhamento(pdf)
      destination = variables['destination'] || variables[:destination]
      specialty   = variables['specialty'] || variables[:specialty]
      reason      = variables['reason'] || variables[:reason]
      professional = variables['professional_name'] || variables[:professional_name] || (generated_by&.name || '—')

      pdf.font_size(11) do
        pdf.text 'ENCAMINHAMENTO', style: :bold, align: :center
        pdf.move_down 12

        pdf.text 'Encaminho o(a) paciente acima identificado(a) para atendimento especializado.'
        pdf.move_down 8
        pdf.text "Especialidade: #{specialty || '_______________'}"
        pdf.text "Para: #{destination || '_______________'}" if destination.present?
        pdf.move_down 8

        if reason.present?
          pdf.text 'Motivo do Encaminhamento:', style: :bold
          pdf.text reason.to_s
        end

        pdf.move_down 30
        pdf.text '___________________________________'
        pdf.text professional.to_s
      end
    end

    def draw_declaracao(pdf)
      content = variables['content'] || variables[:content] || 'Declaro para os devidos fins que o(a) paciente encontra-se em acompanhamento nesta clínica.'
      professional = variables['professional_name'] || variables[:professional_name] || (generated_by&.name || '—')

      pdf.font_size(11) do
        pdf.text content.to_s
        pdf.move_down 30
        pdf.text '___________________________________'
        pdf.text professional.to_s
      end
    end

    def draw_relatorio_clinico(pdf)
      content = variables['content'] || variables[:content] || '...'
      professional = variables['professional_name'] || variables[:professional_name] || (generated_by&.name || '—')

      pdf.font_size(11) do
        pdf.text 'RELATÓRIO CLÍNICO', style: :bold, align: :center
        pdf.move_down 12
        pdf.text content.to_s
        pdf.move_down 30
        pdf.text '___________________________________'
        pdf.text professional.to_s
      end
    end

    def draw_generic(pdf)
      content = variables['content'] || variables[:content] || ''

      pdf.font_size(11) do
        pdf.text content.to_s
        pdf.move_down 30
        pdf.text '___________________________________'
        pdf.text generated_by&.name || '—'
      end
    end

    def draw_footer(pdf)
      pdf.move_down 20
      pdf.stroke_horizontal_rule
      pdf.move_down 4
      pdf.font_size(8) do
        pdf.text "Documento gerado em #{Time.current.strftime('%d/%m/%Y às %H:%M')} por #{generated_by&.name || 'Sistema'}",
                 align: :center, color: '666666'
        pdf.text "Paciente ID ##{patient.id} | #{begin
          patient.account.name
        rescue StandardError
          'BeClinic'
        end}",
                 align: :center, color: '666666'
      end
    end

    def save_document(pdf_data)
      doc = Document.new(
        patient: patient,
        account: patient.account,
        generated_by: generated_by,
        form_template_id: form_template_id,
        document_type: document_type,
        title: title,
        is_generated: true,
        status: 'gerado',
        variables: variables
      )

      # Anexa o PDF gerado via Active Storage
      doc.file.attach(
        io: StringIO.new(pdf_data),
        filename: "#{document_type}-#{patient.id}-v#{doc.version || 1}.pdf",
        content_type: 'application/pdf'
      )

      doc.save!
      doc
    end

    def default_title(type)
      {
        'atestado' => 'Atestado Médico',
        'receita' => 'Receita Médica',
        'pedido_exame' => 'Pedido de Exame',
        'declaracao' => 'Declaração',
        'relatorio_clinico' => 'Relatório Clínico',
        'encaminhamento' => 'Encaminhamento',
        'instrucao_procedimento' => 'Instruções de Procedimento',
        'contrato' => 'Contrato de Prestação de Serviços',
        'orcamento' => 'Orçamento'
      }.fetch(type, type.humanize)
    end

    def days_in_full(days)
      return 'indefinido' unless days.present? && days.to_i > 0

      case days.to_i
      when 1 then 'um'
      when 2 then 'dois'
      when 3 then 'três'
      when 4 then 'quatro'
      when 5 then 'cinco'
      when 6 then 'seis'
      when 7 then 'sete'
      else "#{days}"
      end
    end
  end
end
