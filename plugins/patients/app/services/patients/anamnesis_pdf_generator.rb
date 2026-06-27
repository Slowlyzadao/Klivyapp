# frozen_string_literal: true

module Patients
  class AnamnesisPdfGenerator < Patients::Pdf::BasePdf
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

    def initialize(anamnesis:, actor: nil)
      @anamnesis = anamnesis
      @patient   = anamnesis.patient
      @account   = anamnesis.account
      @actor     = actor || anamnesis.professional
    end

    def call
      pdf_data = super

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

    def header_account_name
      account&.name.to_s
    end

    def header_subtitle
      'Ficha de Anamnese e Questionário de Saúde'
    end

    def footer_document_id
      "#{anamnesis.id} · v#{anamnesis.version_number}"
    end

    def build
      draw_document_meta
      draw_patient_card
      draw_medical_history
      draw_signatures_block
    end

    def draw_document_meta
      pdf.fill_color BG_LIGHT
      pdf.fill_rectangle [0, pdf.cursor], pdf.bounds.width, 24

      pdf.fill_color TEXT_SECONDARY
      pdf.font('Helvetica') do
        pdf.text_box(
          "Especialidade: #{anamnesis.specialty.to_s.titleize.presence || NOT_INFORMED}",
          at: [10, pdf.cursor - 8],
          width: pdf.bounds.width / 2, height: 12, size: 8.5
        )
        pdf.text_box(
          "Data: #{formatted_finalized_at}",
          at: [pdf.bounds.width / 2, pdf.cursor - 8],
          width: pdf.bounds.width / 2 - 10, height: 12, size: 8.5,
          align: :right
        )
      end
      pdf.fill_color TEXT_PRIMARY
      pdf.move_down 36
    end

    def draw_patient_card
      draw_section_title('Dados do Paciente')

      draw_kv_grid(
        [
          ['Nome', patient.name.to_s],
          ['CPF', fmt_cpf(patient.cpf)],
          ['Data de Nascimento', patient.birthdate&.strftime('%d/%m/%Y') || NOT_INFORMED],
          ['Sexo', SEX_TRANSLATIONS[patient.sex.to_s] || NOT_INFORMED]
        ]
      )

      draw_highlight_block(
        label: 'Queixa Principal',
        content: anamnesis.chief_complaint.presence || 'Nenhuma'
      )
    end

    def draw_medical_history
      draw_section_title('Histórico Médico e Condições')

      hm = anamnesis.medical_history || {}
      marked = hm.select { |_, v| v == true || v == 'true' }.keys

      draw_subsection('Sistemas e Condições Marcadas') do
        if marked.any?
          marked.each do |k|
            translated = MEDICAL_CONDITION_TRANSLATIONS[k.to_s] || k.to_s.humanize
            draw_bullet(translated)
          end
        else
          draw_bullet('Nenhuma condição grave marcada.', muted: true)
        end
        if hm['other'].present?
          pdf.move_down 4
          pdf.font('Helvetica') do
            pdf.fill_color TEXT_SECONDARY
            pdf.text "Outras condições: #{hm['other']}", size: 10
            pdf.fill_color TEXT_PRIMARY
          end
        end
      end

      draw_subsection('Alergias Relatadas') do
        if anamnesis.allergies.present?
          anamnesis.allergies.each { |al| draw_bullet(al['name'].to_s) }
        else
          draw_bullet('Nega alergias ou desconhece.', muted: true)
        end
      end

      draw_subsection('Medicamentos de Uso Contínuo') do
        if anamnesis.current_medications.present?
          anamnesis.current_medications.each { |med| draw_bullet(med['name'].to_s) }
        else
          draw_bullet('Nenhum medicamento relatado.', muted: true)
        end
      end

      draw_subsection('Intervenções Anteriores / Cirúrgicas') do
        draw_bullet(anamnesis.surgical_history.presence || 'Nada relatado',
                    muted: anamnesis.surgical_history.blank?)
      end

      draw_subsection('Hábitos Relevantes') do
        rh = anamnesis.relevant_habits || {}
        draw_bullet("Tabagismo: #{rh['smoker'].presence || 'Não'}")
        draw_bullet("Consumo de Álcool: #{rh['alcohol'].presence || 'Não'}")
        draw_bullet("Atividade Física: #{rh['sports'].presence || 'Sedentário'}")
      end

      draw_subsection('Observações Adicionais') do
        notes = anamnesis.additional_notes.presence
        draw_bullet(notes || 'Nenhuma', muted: notes.nil?)
      end
    end

    def draw_signatures_block
      pdf.move_down 8
      pdf.fill_color TEXT_SECONDARY
      pdf.font('Helvetica', style: :italic) do
        pdf.text 'Declaro sob responsabilidade que as informações prestadas são verdadeiras.',
                 align: :center, size: 8.5
      end
      pdf.fill_color TEXT_PRIMARY

      professional_name = actor&.name || anamnesis.professional&.name || 'Profissional Responsável'

      draw_signatures(
        left: {
          name: patient.name,
          caption: 'Assinatura do Paciente'
        },
        right: {
          name: professional_name,
          caption: "Assinado eletronicamente em #{formatted_finalized_at}",
          caption_italic: true
        }
      )
    end

    def formatted_finalized_at
      time = anamnesis.finalized_at || Time.current
      time.in_time_zone('Brasilia').strftime('%d/%m/%Y às %H:%M')
    end
  end
end
