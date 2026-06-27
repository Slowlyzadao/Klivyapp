# Ações do paciente sobre o seu próprio recall (PRD §13bis).
#
# MVP entrega 2 ações:
#   - POST /recall/dismiss → "lembre depois" (zera needs_recall + carimba data)
#   - POST /recall/schedule → atalho que redireciona o front pra /appointments/new
#     (criamos uma intenção em PatientPortalAccessLog para métrica)
#
# Não precisamos de modelo separado — `Patient.needs_recall` + `last_recall_at`
# já existem (migration 20260518000007).
class Api::V1::PatientPortal::RecallController < Api::V1::PatientPortal::BaseController
  # POST /api/v1/patient_portal/recall/dismiss
  def dismiss
    current_patient.update!(needs_recall: false, last_recall_at: Time.current)
    PatientPortalAccessLog.log!(
      account: current_account, patient: current_patient,
      action: 'dismiss', resource: current_patient,
      ip: request.remote_ip, user_agent: request.user_agent,
      metadata: { kind: 'recall' }
    )
    render json: { data: { dismissed: true } }
  end

  # POST /api/v1/patient_portal/recall/schedule_intent
  # Apenas registra que o paciente clicou em "Agendar" a partir do banner de
  # recall. O front cuida do redirect.
  def schedule_intent
    PatientPortalAccessLog.log!(
      account: current_account, patient: current_patient,
      action: 'click', resource: current_patient,
      ip: request.remote_ip, user_agent: request.user_agent,
      metadata: { kind: 'recall_schedule' }
    )
    render json: { data: { recorded: true } }
  end
end
