# app/jobs/patients/record_timeline_event_job.rb
#
# Job que materializa eventos de timeline escrevendo na tabela `patient_timeline_events`.
# Diferente do PatientTimelineEventJob (que escreve no AuditLog), este job constrói
# a Timeline visual do paciente com dados já formatados para exibição.
#
# Uso:
#   Patients::RecordTimelineEventJob.perform_later(
#     patient_id: patient.id,
#     account_id: account.id,
#     actor_id: current_user.id,
#     event_type: 'appointment_scheduled',
#     label: 'Consulta agendada para 10/04/2026',
#     reference_type: 'PatientAppointment',
#     reference_id: appointment.id,
#     metadata: { ... }
#   )

module Patients
  class RecordTimelineEventJob < ApplicationJob
    queue_as :patients

    sidekiq_options retry: 5, dead: true

    def perform(
      patient_id:,
      account_id:,
      actor_id:,
      event_type:,
      label:,
      reference_type: nil,
      reference_id:   nil,
      metadata:       {},
      occurred_at:    nil
    )
      patient = Patient.find_by(id: patient_id)
      account = Account.find_by(id: account_id)

      unless patient && account
        Rails.logger.warn("[RecordTimelineEventJob] patient=#{patient_id} ou account=#{account_id} não encontrado")
        return
      end

      actor = User.find_by(id: actor_id)

      PatientTimelineEvent.record!(
        patient: patient,
        account: account,
        actor: actor,
        event_type: event_type.to_s,
        label: label,
        reference: build_reference(reference_type, reference_id),
        metadata: metadata,
        occurred_at: occurred_at ? Time.parse(occurred_at.to_s) : Time.current
      )

      # Também registra no AuditLog para rastreabilidade legal
      PatientAuditLog.log!(
        account: account,
        patient: patient,
        actor: actor,
        action: map_audit_action(event_type),
        resource_type: reference_type,
        resource_id: reference_id,
        changes: metadata.merge(event_type: event_type, description: label)
      )

      Rails.logger.info("[RecordTimelineEventJob] evento=#{event_type} patient=#{patient_id} gravado com sucesso")
    rescue StandardError => e
      Rails.logger.error("[RecordTimelineEventJob] Falha: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}")
      raise # Permite retry do Sidekiq
    end

    private

    def build_reference(reference_type, reference_id)
      return nil if reference_type.blank? || reference_id.blank?

      reference_type.constantize.find_by(id: reference_id)
    rescue NameError
      nil
    end

    def map_audit_action(event_type)
      case event_type.to_s
      when /created/, /scheduled/, /generated/, /uploaded/    then 'create'
      when /signed/, /finalized/                               then 'sign'
      when /updated/, /rescheduled/, /status_changed/          then 'update'
      when /canceled/, /deleted/                               then 'delete'
      when /payment/, /refund/                                 then 'pay'
      when /sent/, /recall/                                    then 'send_whatsapp'
      else 'view'
      end
    end
  end
end
