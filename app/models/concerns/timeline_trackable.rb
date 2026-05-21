# frozen_string_literal: true

# Concern que registra automaticamente eventos na timeline do paciente.
# Incluir nos models que devem gerar eventos (AgendaEvent, TreatmentPlan, etc.)
#
# Uso: include TimelineTrackable
#
# O model deve responder a:
#   - timeline_patient  → Patient (obrigatório)
#   - timeline_account  → Account (obrigatório)
#
# Cada model implementa seus próprios métodos de callback que chamam
# `record_timeline_event!` para registrar o evento.
module TimelineTrackable
  extend ActiveSupport::Concern

  private

  def record_timeline_event!(event_type:, label:, actor: nil, reference: nil, metadata: {}, occurred_at: Time.current)
    patient  = respond_to?(:timeline_patient, true) ? timeline_patient : try(:patient)
    account  = respond_to?(:timeline_account, true) ? timeline_account : try(:account)

    return unless patient.present? && account.present?

    PatientTimelineEvent.record!(
      patient: patient,
      account: account,
      event_type: event_type,
      label: label,
      actor: actor,
      reference: reference || self,
      metadata: metadata,
      occurred_at: occurred_at
    )
  end
end
