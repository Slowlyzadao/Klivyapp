# frozen_string_literal: true

# Gera o prontuário eletrônico completo do paciente (cópia integral) em PDF.
# Resultado é exposto como binário via `Result.pdf_data` para download direto.
# Cada exportação registra `PatientAuditLog#export` para conformidade LGPD.
module Patients
  class RecordPdfGenerator < Patients::Pdf::BasePdf
    Result = Struct.new(:success?, :pdf_data, :error, keyword_init: true)

    ALERT_INTENT = {
      'critico'  => :danger,
      'critical' => :danger,
      'alto'     => :danger,
      'high'     => :danger,
      'medio'    => :warning,
      'medium'   => :warning,
      'baixo'    => :info,
      'low'      => :info
    }.freeze

    def self.call(**args)
      new(**args).run
    end

    def initialize(patient:, generated_by:, ip_address: nil)
      @patient      = patient
      @account      = patient.account
      @generated_by = generated_by
      @ip_address   = ip_address
    end

    def run
      pdf_data = call

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

    def header_account_name
      account&.name.to_s
    end

    def header_subtitle
      'Prontuário Eletrônico — Cópia Integral'
    end

    def footer_document_id
      "Paciente #{patient.id}"
    end

    def build
      draw_intro_block
      draw_administrative_data
      draw_critical_alerts
      draw_anamneses
      draw_clinical_notes
      draw_treatment_plans
      draw_documents_and_consents
      draw_audit_logs
      draw_confidentiality_notice
    end

    def draw_intro_block
      draw_kv_grid(
        [
          ['Paciente', patient.name.to_s],
          ['CPF', fmt_cpf(patient.cpf)],
          ['Gerado em', fmt_datetime(Time.current)],
          ['Gerado por', generated_by&.name || 'Sistema']
        ]
      )
    end

    def draw_administrative_data
      draw_section_title('Dados Cadastrais')

      draw_kv_grid(
        [
          ['Nome', patient.name.to_s],
          ['CPF', fmt_cpf(patient.cpf)],
          ['RG', patient.rg.to_s.presence || '—'],
          ['Data de Nascimento', patient.birthdate&.strftime('%d/%m/%Y') || '—'],
          ['Idade', patient.age ? "#{patient.age} anos" : '—'],
          ['Sexo', patient.sex&.humanize || '—'],
          ['Celular/WhatsApp', patient.phone.to_s.presence || '—'],
          ['E-mail', patient.email.to_s.presence || '—'],
          ['Status', patient.patient_status.to_s.humanize.presence || '—']
        ]
      )

      if patient.address.present?
        draw_highlight_block(label: 'Endereço', content: patient.full_address.to_s)
      end

      ec = patient.emergency_contact
      return unless ec.is_a?(Hash) && ec['name'].present?

      draw_highlight_block(
        label: 'Contato de Emergência',
        content: "#{ec['name']} (#{ec['relationship']}) — #{ec['phone']}"
      )
    end

    def draw_critical_alerts
      alerts = patient.critical_alerts.active.to_a
      return if alerts.empty?

      draw_section_title('Alertas Críticos')

      alerts.each do |alert|
        intent = ALERT_INTENT[alert.severity.to_s.downcase] || :warning
        ensure_space(50)
        draw_centered_badge("#{alert.severity.to_s.upcase} · #{alert.alert_type.to_s.humanize}", intent: intent)
        draw_highlight_block(
          label: alert.label.to_s,
          content: alert.description.to_s.presence || '—',
          color: intent == :danger ? DANGER : (intent == :warning ? WARNING_DARK : PRIMARY)
        )
      end
    end

    def draw_anamneses
      draw_section_title('Histórico de Anamnese')

      anamneses = patient.anamneses.active.order(version_number: :desc).to_a
      return draw_empty('Nenhuma anamnese registrada.') if anamneses.empty?

      anamneses.each do |anam|
        ensure_space(80)
        draw_subsection("Versão ##{anam.version_number} — #{anam.finalized_at ? "Finalizada em #{fmt_datetime(anam.finalized_at)}" : 'Em rascunho'}") do
          draw_kv_grid(
            [
              ['Especialidade', anam.specialty.to_s.humanize.presence || '—'],
              ['Queixa Principal', anam.chief_complaint.to_s.presence || '—']
            ],
            columns: 1
          )

          if anam.allergies.present?
            pdf.font('Helvetica', style: :bold) { pdf.text 'Alergias:', size: 9 }
            anam.allergies.each do |al|
              draw_bullet("#{al['substance']} (Reação: #{al['reaction']}, Severidade: #{al['severity']})")
            end
          end

          if anam.current_medications.present?
            pdf.font('Helvetica', style: :bold) { pdf.text 'Medicamentos em uso:', size: 9 }
            anam.current_medications.each do |med|
              draw_bullet("#{med['name']} (#{med['frequency']})")
            end
          end

          if anam.additional_notes.present?
            draw_highlight_block(label: 'Observações', content: anam.additional_notes.to_s)
          end
        end
      end
    end

    def draw_clinical_notes
      draw_section_title('Evolução Clínica')

      notes = patient.clinical_notes.active.order(note_date: :asc).to_a
      return draw_empty('Nenhuma evolução registrada.') if notes.empty?

      notes.each do |note|
        ensure_space(100)
        title = "#{fmt_date(note.note_date)} · #{note.professional&.name || '—'}"
        draw_subsection(title) do
          draw_centered_badge(note.status.to_s.upcase, intent: note.status.to_s == 'assinada' ? :success : :info)
          pdf.move_down 4
          draw_kv_grid(
            [
              ['Assinada em', note.signed_at ? fmt_datetime(note.signed_at) : '—']
            ],
            columns: 1
          ) if note.signed_at.present?

          draw_highlight_block(label: 'Queixa', content: note.complaint_of_day.to_s) if note.complaint_of_day.present?
          draw_highlight_block(label: 'Avaliação', content: note.assessment.to_s) if note.assessment.present?
          draw_highlight_block(label: 'Conduta', content: note.conduct.to_s) if note.conduct.present?
          draw_highlight_block(label: 'Orientações', content: note.guidance_given.to_s) if note.guidance_given.present?
        end
      end
    end

    def draw_treatment_plans
      draw_section_title('Planos de Tratamento e Sessões')

      plans = patient.treatment_plans.active.order(created_at: :asc).to_a
      return draw_empty('Nenhum plano de tratamento registrado.') if plans.empty?

      plans.each do |plan|
        ensure_space(100)
        title = "Plano ##{plan.id} · #{plan.status.to_s.humanize.upcase} · Criado em #{fmt_date(plan.created_at)}"
        draw_subsection(title) do
          items = plan.treatment_items.active.to_a
          if items.empty?
            draw_empty('Sem procedimentos cadastrados.')
            next
          end

          item_rows = items.map do |item|
            sessions_text = "#{item.sessions_done.to_i}/#{item.sessions_planned.to_i}"
            [item.procedure_name.to_s, sessions_text]
          end
          draw_data_table(['Procedimento', 'Sessões'], item_rows, col_widths: [380, 115], number_columns: [1])

          items.each do |item|
            sessions = patient.session_logs.active.where(treatment_item_id: item.id).order(performed_at: :asc).to_a
            next if sessions.empty?

            pdf.move_down 4
            pdf.font('Helvetica', style: :bold) { pdf.text "Sessões — #{item.procedure_name}:", size: 9 }
            sessions.each do |session|
              draw_bullet("#{fmt_date(session.performed_at)} — #{session.result_observed}")
            end
          end
        end
      end
    end

    def draw_documents_and_consents
      draw_section_title('Documentos, Exames e Consentimentos')

      exams = patient.exam_medias.active.order(created_at: :asc).to_a
      docs = patient.documents.active.order(created_at: :asc).to_a
      consents = patient.consent_records.active.order(created_at: :asc).to_a

      if exams.any?
        draw_subsection('Exames / Mídias') do
          rows = exams.map { |e| [e.category.to_s.humanize, e.file_name.to_s, fmt_date(e.created_at)] }
          draw_data_table(['Categoria', 'Arquivo', 'Data'], rows, col_widths: [120, 280, 95])
        end
      end

      if docs.any?
        draw_subsection('Documentos Gerados') do
          rows = docs.map { |d| [d.document_type.to_s.humanize, d.title.to_s, d.status.to_s.humanize, fmt_date(d.created_at)] }
          draw_data_table(['Tipo', 'Título', 'Status', 'Data'], rows, col_widths: [110, 220, 80, 85])
        end
      end

      if consents.any?
        draw_subsection('Termos de Consentimento') do
          consents.each do |consent|
            label = "#{consent.title} · #{consent.status.to_s.upcase}"
            caption = consent.signed_at.present? ? "Assinado em #{fmt_datetime(consent.signed_at)} (IP: #{consent.ip_address})" : '—'
            draw_highlight_block(label: label, content: caption)
          end
        end
      end

      return if exams.any? || docs.any? || consents.any?

      draw_empty('Nenhum documento, exame ou consentimento registrado.')
    end

    def draw_audit_logs
      draw_section_title('Auditoria de Prontuário (Últimos Registros)')

      logs = patient.patient_audit_logs.ordered.limit(20).to_a
      return draw_empty('Nenhum log de auditoria encontrado.') if logs.empty?

      rows = logs.map do |log|
        [
          log.occurred_at ? fmt_datetime(log.occurred_at) : '—',
          log.actor_name.to_s.presence || 'Sistema',
          log.action.to_s.upcase,
          log.resource_type.to_s.presence || 'Patient'
        ]
      end
      draw_data_table(['Quando', 'Quem', 'Ação', 'Recurso'], rows, col_widths: [140, 175, 100, 80])
    end

    def draw_confidentiality_notice
      pdf.move_down 12
      pdf.fill_color TEXT_MUTED
      pdf.font('Helvetica', style: :italic) do
        pdf.text 'Este documento é confidencial e protegido por sigilo profissional.', size: 8.5, align: :center
        pdf.text 'Qualquer compartilhamento não autorizado infringe as diretrizes da LGPD.', size: 8.5, align: :center
        pdf.text "IP de origem: #{ip_address || '—'}", size: 8, align: :center
      end
      pdf.fill_color TEXT_PRIMARY
    end
  end
end
