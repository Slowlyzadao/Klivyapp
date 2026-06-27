# Payload agregado da home (PRD §6.2). A partir da Sprint C, próxima consulta
# e documentos recentes já vêm preenchidos. Financeiro entra na Sprint D.
class Api::V1::PatientPortal::HomeController < Api::V1::PatientPortal::BaseController
  def show
    appts = PatientPortal::AppointmentVisibility.new(patient: current_patient, account: current_account)
    docs  = PatientPortal::DocumentVisibility.new(patient: current_patient, account: current_account)
    fin   = PatientPortal::FinancialSummary.new(patient: current_patient, account: current_account)
    pending_consents = PatientPortal::ConsentRecordVisibility.new(patient: current_patient, account: current_account)
                                                              .pending.count
    restriction = PatientPortal::OverdueRestrictionChecker.new(
      account: current_account, patient: current_patient
    ).call

    render json: {
      data: {
        patient: { id: current_patient.id, name: current_patient.name },
        account: { id: current_account.id, name: current_account.name },
        cards: {
          next_appointment:        serialize_event(appts.next_event),
          financial_summary:       fin.totals,
          unread_messages_count:   unread_notifications_count,
          documents_recent:        docs.recent(limit: 5).map { |d| serialize_doc(d) },
          pending_consents_count:  pending_consents,
          consent_pending_blocking: pending_consents.positive?,
          recall_due:              current_patient.needs_recall,
          overdue_restriction:     restriction.to_h
        }
      }
    }
  end

  private

  def unread_notifications_count
    PatientPortalNotification.where(account_id: current_account.id, patient_id: current_patient.id)
                              .unread.count
  end

  def serialize_event(e)
    return nil if e.blank?

    telemed = Telemed::Session.new(event: e, account: current_account).call

    {
      id:           e.id,
      title:        e.title,
      status:       e.status,
      starts_at:    e.starts_at,
      ends_at:      e.ends_at,
      professional: e.user          ? { id: e.user.id, name: e.user.name } : nil,
      service:      e.agenda_service ? { id: e.agenda_service.id, name: e.agenda_service.name } : nil,
      telemedicine: telemed.to_h
    }
  end

  def serialize_doc(d)
    {
      id:            d.id,
      title:         d.title,
      document_type: d.document_type,
      created_at:    d.created_at,
      download_path: "/api/v1/patient_portal/documents/#{d.id}/download"
    }
  end
end
