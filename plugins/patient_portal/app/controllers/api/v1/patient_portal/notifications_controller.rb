# Endpoints de notificações in-app do paciente (PRD §13ter).
# Sprint E migrou do stub para `PatientPortalNotification` real.
class Api::V1::PatientPortal::NotificationsController < Api::V1::PatientPortal::BaseController
  LIST_LIMIT = 50

  # GET /api/v1/patient_portal/notifications
  def index
    base = PatientPortalNotification.for_patient(current_patient.id)
                                    .where(account_id: current_account.id)
                                    .recent_first
                                    .limit(LIST_LIMIT)

    render json: {
      data: {
        unread_count: base.unread.count,
        items:        base.map { |n| serialize(n) }
      }
    }
  end

  # POST /api/v1/patient_portal/notifications/mark_all_read
  def mark_all_read
    PatientPortalNotification.for_patient(current_patient.id)
                              .where(account_id: current_account.id)
                              .unread
                              .update_all(read_at: Time.current, updated_at: Time.current)

    render json: { data: { ok: true } }
  end

  # POST /api/v1/patient_portal/notifications/:id/mark_read
  def mark_read
    notif = PatientPortalNotification.for_patient(current_patient.id)
                                      .where(account_id: current_account.id)
                                      .find(params[:id])
    notif.mark_read!
    render json: { data: serialize(notif) }
  end

  private

  def serialize(n)
    {
      id:         n.id,
      kind:       n.kind,
      title:      n.title,
      body:       n.body,
      payload:    n.payload,
      created_at: n.created_at,
      read:       n.read?
    }
  end
end
