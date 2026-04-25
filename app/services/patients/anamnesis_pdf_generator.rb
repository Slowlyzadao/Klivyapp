# frozen_string_literal: true

module Patients
  class AnamnesisPdfGenerator
    MEDICAL_CONDITION_TRANSLATIONS = {
      'diabetes' => 'Diabetes',
      'oncology' => 'Tratamento Oncológico (Atual ou prévio)',
      'pregnant' => 'Gestante / Lactante',
      'hepatitis' => 'Hepatite / Doenças Hepáticas',
      'has_implants' => 'Possui Implantes ou Próteses',
      'hypertension' => 'Hipertensão ou problemas cardiovasculares',
      'bleeding_disorder' => 'Distúrbios de coagulação / hemorragia',
      'has_recent_surgeries' => 'Cirurgias Recentes',
      'has_anesthesia_complications' => 'Complicações com Anestesia'
    }.freeze

    SEX_TRANSLATIONS = {
      'masculino' => 'Masculino',
      'feminino' => 'Feminino',
      'outro' => 'Outro',
      'nao_informado' => 'Não informado'
    }.freeze

    NOT_INFORMED = 'Não informado'

    def self.call(**args)
      new(**args).call
    end

    def initialize(anamnesis:, actor: nil)
      @anamnesis = anamnesis
      @patient = anamnesis.patient
      @account = anamnesis.account
      @actor = actor || anamnesis.professional
    end

    def call
      pdf_data = generate_pdf

      # Anexar o PDF gerado diretamente à Anamnesis usando attach com io
      @anamnesis.pdf.attach(
        io: StringIO.new(pdf_data),
        filename: "anamnese_#{@patient.name.parameterize}_v#{@anamnesis.version_number}_#{@anamnesis.id}.pdf",
        content_type: 'application/pdf'
      )

      true
    rescue StandardError => e
      Rails.logger.error("[AnamnesisPdfGenerator] Erro ao gerar/anexar PDF: #{e.message}")
      false
    end

    private

    attr_reader :anamnesis, :patient, :account, :actor

    def generate_pdf
      require 'prawn'
      Prawn::Fonts::AFM.hide_m17n_warning = true

      pdf = Prawn::Document.new(page_size: 'A4', margin: [50, 50, 60, 50])

      draw_header(pdf)
      draw_patient_data(pdf)
      draw_medical_history(pdf)
      draw_footer(pdf)

      pdf.render
    end

    def draw_header(pdf)
      pdf.font_size(20) { pdf.text account.name, style: :bold, align: :center }
      pdf.move_down 10
      pdf.font_size(14) { pdf.text 'FICHA DE ANAMNESE E QUESTIONÁRIO DE SAÚDE', style: :bold, align: :center }
      pdf.move_down 5
      pdf.font_size(10) { pdf.text "Especialidade: #{anamnesis.specialty.to_s.titleize}", align: :center }
      pdf.move_down 25
    end

    def draw_patient_data(pdf)
      pdf.font_size(12) { pdf.text 'DADOS DO PACIENTE', style: :bold }
      pdf.move_down 5
      pdf.font_size(10) do
        pdf.text "Nome: #{patient.name}"
        pdf.text "CPF: #{patient.cpf.presence || NOT_INFORMED} | " \
                "Data de Nascimento: #{patient.birthdate&.strftime('%d/%m/%Y') || NOT_INFORMED}"
        pdf.text "Sexo: #{SEX_TRANSLATIONS[patient.sex.to_s] || NOT_INFORMED}"
        pdf.text "Queixa Principal: #{anamnesis.chief_complaint.presence || 'Nenhuma'}", style: :italic
      end
      pdf.move_down 20
    end

    def formatted_finalized_at
      time = anamnesis.finalized_at || Time.current
      time.in_time_zone('Brasilia').strftime('%d/%m/%Y às %H:%M')
    end

    def draw_medical_history(pdf)
      pdf.font_size(12) { pdf.text 'HISTÓRICO MÉDICO E CONDIÇÕES', style: :bold }
      pdf.move_down 10

      pdf.font_size(10) do
        pdf.text 'Sistemas e Condições Marcadas:', style: :bold
        hm = anamnesis.medical_history || {}
        marked = hm.select { |_, v| v == true || v == 'true' }.keys
        if marked.any?
          marked.each do |k|
            translated_key = MEDICAL_CONDITION_TRANSLATIONS[k.to_s] || k.to_s.humanize
            pdf.text "  - #{translated_key}"
          end
        else
          pdf.text '  - Nenhuma condição grave marcada.'
        end
        pdf.text "Outras condições: #{hm['other']}" if hm['other'].present?
        pdf.move_down 10

        pdf.text 'Alergias Relatadas:', style: :bold
        if anamnesis.allergies.present?
          anamnesis.allergies.each { |al| pdf.text "  - #{al['name']}" }
        else
          pdf.text '  - Nega alergias ou desconhece.'
        end
        pdf.move_down 10

        pdf.text 'Medicamentos de Uso Contínuo:', style: :bold
        if anamnesis.current_medications.present?
          anamnesis.current_medications.each { |med| pdf.text "  - #{med['name']}" }
        else
          pdf.text '  - Nenhum medicamento relatado.'
        end
        pdf.move_down 10

        pdf.text 'Intervenções Anteriores/Cirúrgicas:', style: :bold
        pdf.text "  - #{anamnesis.surgical_history.presence || 'Nada relatado'}"
        pdf.move_down 10

        pdf.text 'Hábitos Relevantes:', style: :bold
        rh = anamnesis.relevant_habits || {}
        pdf.text "  - Tabagismo: #{rh['smoker'].presence || 'Não'}"
        pdf.text "  - Consumo de Álcool: #{rh['alcohol'].presence || 'Não'}"
        pdf.text "  - Atividade Física: #{rh['sports'].presence || 'Sedentário'}"
        pdf.move_down 10

        pdf.text 'Observações Adicionais:', style: :bold
        pdf.text "  - #{anamnesis.additional_notes.presence || 'Nenhuma'}"
      end
    end

    def draw_footer(pdf)
      pdf.move_down 50
      pdf.text 'Declaro sob responsabilidade que as informações prestadas são verdadeiras.',
               align: :center, size: 9, style: :italic

      pdf.move_down 40
      pdf.stroke_horizontal_rule
      pdf.move_down 5
      pdf.text patient.name, align: :center, size: 10, style: :bold
      pdf.text 'Assinatura do Paciente', align: :center, size: 8

      pdf.move_down 40
      pdf.stroke_horizontal_rule
      pdf.move_down 5
      professional_name = actor&.name || anamnesis.professional&.name || 'Profissional Responsável'
      pdf.text professional_name, align: :center, size: 10, style: :bold
      pdf.text "Assinado eletronicamente em #{formatted_finalized_at}",
               align: :center, size: 8, style: :italic
    end
  end
end
