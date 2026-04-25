# frozen_string_literal: true

module Patients
  class RecordPdfGenerator
    Result = Struct.new(:success?, :pdf_data, :error, keyword_init: true)

    def self.call(**args)
      new(**args).call
    end

    def initialize(patient:, generated_by:, ip_address: nil)
      @patient      = patient
      @account      = patient.account
      @generated_by = generated_by
      @ip_address   = ip_address
    end

    def call
      pdf_data = generate_pdf

      PatientAuditLog.log!(
        account: @account,
        patient: @patient,
        action: 'export',
        actor: @generated_by,
        resource: @patient,
        ip_address: @ip_address
      )

      Result.new(success?: true, pdf_data: pdf_data, error: nil)
    rescue StandardError => e
      Rails.logger.error("[RecordPdfGenerator] Erro ao gerar PDF do Prontuário: #{e.message}")
      Result.new(success?: false, pdf_data: nil, error: e.message)
    end

    private

    attr_reader :patient, :account, :generated_by, :ip_address

    def generate_pdf
      require 'prawn'

      pdf = Prawn::Document.new(page_size: 'A4', margin: [50, 50, 60, 50])

      draw_cover(pdf)
      pdf.start_new_page

      draw_administrative_data(pdf)
      draw_critical_alerts(pdf)

      pdf.start_new_page
      draw_anamneses(pdf)

      pdf.start_new_page
      draw_clinical_notes(pdf)

      pdf.start_new_page
      draw_treatment_plans(pdf)

      pdf.start_new_page
      draw_documents_and_consents(pdf)

      pdf.start_new_page
      draw_audit_logs(pdf)

      draw_footer(pdf)

      pdf.render
    end

    def draw_cover(pdf)
      pdf.move_down 100
      pdf.font_size(24) { pdf.text account.name, style: :bold, align: :center }
      pdf.move_down 20
      pdf.font_size(18) { pdf.text 'PRONTUÁRIO ELETRÔNICO DO PACIENTE (CÓPIA INTEGRAL)', style: :bold, align: :center }
      pdf.move_down 40

      pdf.font_size(14) do
        pdf.text "Paciente: #{patient.name}", align: :center
        pdf.text "CPF: #{patient.cpf.presence || 'Não informado'}", align: :center
        pdf.text "Gerado em: #{Time.current.strftime('%d/%m/%Y às %H:%M')}", align: :center
        pdf.text "Gerado por: #{generated_by&.name || 'Sistema'}", align: :center
      end

      pdf.move_down 100
      pdf.font_size(10) do
        pdf.text 'Este documento é confidencial e protegido por sigilo profissional.', align: :center, style: :italic
        pdf.text 'Qualquer compartilhamento não autorizado infringe as diretrizes da LGPD.', align: :center, style: :italic
      end
    end

    def draw_administrative_data(pdf)
      section_title(pdf, 'DADOS CADASTRAIS')

      pdf.text "Nome: #{patient.name}", style: :bold
      pdf.text "CPF: #{patient.cpf}   |   RG: #{patient.rg}"
      pdf.text "Data de Nascimento: #{patient.birthdate&.strftime('%d/%m/%Y')}   |   Idade: #{patient.age} anos"
      pdf.text "Sexo: #{patient.sex&.humanize}"
      pdf.text "Celular/WhatsApp: #{patient.phone}"
      pdf.text "E-mail: #{patient.email}"
      pdf.text "Status: #{patient.patient_status.to_s.humanize}"
      pdf.move_down 10

      if patient.address.present?
        pdf.text "Endereço: #{patient.full_address}"
        pdf.move_down 5
      end

      return unless patient.emergency_contact.present?

      ec = patient.emergency_contact || {}
      pdf.text "Contato de Emergência: #{ec['name']} (#{ec['relationship']}) - #{ec['phone']}"
    end

    def draw_critical_alerts(pdf)
      alerts = patient.critical_alerts.active
      return if alerts.empty?

      pdf.move_down 20
      section_title(pdf, 'ALERTAS CRÍTICOS')

      alerts.each do |alert|
        pdf.text "• [#{alert.severity.upcase}] #{alert.alert_type.humanize}: #{alert.label}"
        pdf.text "  Nota: #{alert.description}" if alert.description.present?
      end
    end

    def draw_anamneses(pdf)
      section_title(pdf, 'HISTÓRICO DE ANAMNESE')

      anamneses = patient.anamneses.active.order(version_number: :desc)
      if anamneses.empty?
        pdf.text 'Nenhuma anamnese registrada.', style: :italic
        return
      end

      anamneses.each do |anam|
        pdf.move_down 10
        pdf.text "Versão ##{anam.version_number} - Finalizada em: #{anam.finalized_at&.strftime('%d/%m/%Y %H:%M') || 'Em rascunho'}", style: :bold
        pdf.text "Especialidade: #{anam.specialty&.humanize}"
        pdf.text "Queixa Principal: #{anam.chief_complaint}"

        if anam.allergies.present?
          pdf.text 'Alergias:'
          anam.allergies.each { |al| pdf.text "  - #{al['substance']} (Reação: #{al['reaction']}, Severidade: #{al['severity']})" }
        end

        if anam.current_medications.present?
          pdf.text 'Medicamentos em uso:'
          anam.current_medications.each { |med| pdf.text "  - #{med['name']} (#{med['frequency']})" }
        end

        pdf.text "Observações: #{anam.additional_notes}" if anam.additional_notes.present?
        pdf.move_down 5
        pdf.stroke_horizontal_rule
      end
    end

    def draw_clinical_notes(pdf)
      section_title(pdf, 'EVOLUÇÃO CLÍNICA')

      notes = patient.clinical_notes.active.order(note_date: :asc)
      if notes.empty?
        pdf.text 'Nenhuma evolução registrada.', style: :italic
        return
      end

      notes.each do |note|
        pdf.move_down 10
        pdf.text "Data: #{note.note_date&.strftime('%d/%m/%Y')} | Profissional: #{note.professional&.name}", style: :bold
        pdf.text "Status: #{note.status.upcase}"
        pdf.text "Assinada em: #{note.signed_at&.strftime('%d/%m/%Y %H:%M')}" if note.signed_at.present?

        pdf.move_down 5
        pdf.text "Queixa: #{note.complaint_of_day}" if note.complaint_of_day.present?
        pdf.text "Avaliação: #{note.assessment}" if note.assessment.present?
        pdf.text "Conduta: #{note.conduct}" if note.conduct.present?
        pdf.text "Orientações: #{note.guidance_given}" if note.guidance_given.present?
        pdf.move_down 5
        pdf.stroke_horizontal_rule
      end
    end

    def draw_treatment_plans(pdf)
      section_title(pdf, 'PLANOS DE TRATAMENTO E SESSÕES')

      plans = patient.treatment_plans.active.order(created_at: :asc)
      if plans.empty?
        pdf.text 'Nenhum plano de tratamento registrado.', style: :italic
        return
      end

      plans.each do |plan|
        pdf.move_down 10
        pdf.text "Plano ##{plan.id} | Status: #{plan.status.upcase} | Criado em: #{plan.created_at.strftime('%d/%m/%Y')}", style: :bold

        items = plan.treatment_items.active
        items.each do |item|
          pdf.text "  -> #{item.procedure_name} (Sessões: #{item.sessions_done} realizadas de #{item.sessions_planned})"

          sessions = patient.session_logs.active.where(treatment_item_id: item.id).order(performed_at: :asc)
          sessions.each do |session|
            pdf.text "      Sessão em #{session.performed_at&.strftime('%d/%m/%Y')}: #{session.result_observed}"
          end
        end
        pdf.move_down 5
        pdf.stroke_horizontal_rule
      end
    end

    def draw_documents_and_consents(pdf)
      section_title(pdf, 'DOCUMENTOS E EXAMES (ÍNDICE)')

      exams = patient.exam_medias.active.order(created_at: :asc)
      if exams.any?
        pdf.text 'Exames / Mídias:', style: :bold
        exams.each do |exam|
          pdf.text "  - [#{exam.category.humanize}] #{exam.file_name} (#{exam.created_at.strftime('%d/%m/%Y')})"
        end
        pdf.move_down 10
      end

      docs = patient.documents.active.order(created_at: :asc)
      if docs.any?
        pdf.text 'Documentos Gerados:', style: :bold
        docs.each do |doc|
          pdf.text "  - [#{doc.document_type.humanize}] #{doc.title} (Status: #{doc.status}, #{doc.created_at.strftime('%d/%m/%Y')})"
        end
        pdf.move_down 10
      end

      consents = patient.consent_records.active.order(created_at: :asc)
      return unless consents.any?

      pdf.text 'Termos de Consentimento:', style: :bold
      consents.each do |consent|
        pdf.text "  - #{consent.title} | Status: #{consent.status.upcase}"
        pdf.text "    Assinado em: #{consent.signed_at&.strftime('%d/%m/%Y %H:%M')} (IP: #{consent.ip_address})" if consent.signed_at.present?
      end
    end

    def draw_audit_logs(pdf)
      section_title(pdf, 'AUDITORIA DE PRONTUÁRIO (Últimos Registros)')

      logs = patient.patient_audit_logs.ordered.limit(20)
      if logs.empty?
        pdf.text 'Nenhum log de auditoria encontrado.', style: :italic
        return
      end

      logs.each do |log|
        pdf.text "[#{log.occurred_at&.strftime('%d/%m/%Y %H:%M:%S')}] #{log.actor_name || 'Sistema'} (#{log.action.upcase}) em #{log.resource_type || 'Patient'}"
      end
    end

    def section_title(pdf, text)
      pdf.font_size(14) { pdf.text text, style: :bold, color: '003366' }
      pdf.move_down 5
      pdf.stroke_color '003366'
      pdf.stroke_horizontal_rule
      pdf.stroke_color '000000'
      pdf.move_down 10
    end

    def draw_footer(pdf)
      number_pages_string = 'Página <page> de <total>'
      options = {
        at: [pdf.bounds.right - 150, 0],
        width: 150,
        align: :right,
        page_filter: :all,
        start_count_at: 1,
        color: '999999',
        size: 9
      }
      pdf.number_pages number_pages_string, options

      # Footer text
      pdf.repeat(:all) do
        pdf.bounding_box([pdf.bounds.left, 20], width: pdf.bounds.width) do
          pdf.stroke_horizontal_rule
          pdf.move_down 4
          id_text = "Doc. Auditável | IP: #{@ip_address} | Gerador: #{@generated_by&.name || 'System'}"
          pdf.font_size(8) do
            pdf.text id_text, color: '999999', align: :left
          end
        end
      end
    end
  end
end
