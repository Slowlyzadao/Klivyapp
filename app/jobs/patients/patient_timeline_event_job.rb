# app/jobs/patients/patient_timeline_event_job.rb
#
# Job central de registro de eventos na timeline do paciente.
# Usado por TODOS os módulos (Anamnese, Evolução, Plano de Tratamento,
# Financeiro, Mídia, etc.) para gerar entradas unificadas na timeline.
#
# Uso:
#   Patients::PatientTimelineEventJob.perform_later(
#     patient_id:  patient.id,
#     account_id:  account.id,
#     actor_id:    current_user.id,
#     event_type:  'anamnesis_finalized',
#     resource_type: 'Anamnesis',
#     resource_id:   anamnesis.id,
#     description: 'Anamnese finalizada pelo profissional',
#     metadata:    { version: anamnesis.version_number }
#   )

module Patients
  class PatientTimelineEventJob < ApplicationJob
    queue_as :patients

    sidekiq_options retry: 5, dead: true

    VALID_EVENT_TYPES = %w[
      patient_created
      patient_updated
      status_changed
      anamnesis_created
      anamnesis_finalized
      clinical_note_created
      clinical_note_signed
      critical_alert_created
      critical_alert_deactivated
      appointment_created
      appointment_cancelled
      appointment_completed
      no_show
      treatment_plan_created
      treatment_plan_approved
      session_logged
      session_signed
      session_log_patient_signed
      session_log_patient_signature_link_sent
      payment_received
      payment_overdue
      document_generated
      consent_signed
      media_uploaded
    ].freeze

    def perform(
      patient_id:,
      account_id:,
      actor_id:,
      event_type:,
      resource_type: nil,
      resource_id:   nil,
      description:   nil,
      metadata:      {}
    )
      # Valida event_type para evitar lixo no histórico
      unless VALID_EVENT_TYPES.include?(event_type.to_s)
        Rails.logger.warn("[PatientTimelineEventJob] event_type inválido: #{event_type}")
        return
      end

      # Registra no PatientAuditLog de forma assíncrona
      patient = Patient.find_by(id: patient_id)
      account = Account.find_by(id: account_id)
      actor   = User.find_by(id: actor_id)

      return unless patient && account

      PatientAuditLog.log!(
        account: account,
        patient: patient,
        actor: actor,
        action: map_action(event_type),
        resource_type: resource_type,
        resource_id: resource_id,
        changes: metadata.merge(
          event_type: event_type,
          description: description
        )
      )

      Rails.logger.info("[PatientTimelineEventJob] event=#{event_type} patient=#{patient_id}")
    end

    private

    def map_action(event_type)
      case event_type.to_s
      when /created/          then 'create'
      when /finalized/        then 'finalize'
      when /signed/           then 'sign'
      when /approved/         then 'approve'
      when /payment/          then 'pay'
      when /export/, /print/  then 'export'
      when /updated/          then 'update'
      when /deleted/, /cancelled/ then 'delete'
      else                    'view'
      end
    end
  end
end
