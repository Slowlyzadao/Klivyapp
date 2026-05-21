# Despacha Web Push em background, fora do request do paciente (Sprint G).
#
# Mantemos isolado em job porque envios de push são I/O para FCM/Mozilla/Apple
# e podem ter latência de centenas de ms — não pode bloquear request da clínica
# ao confirmar consulta, registrar pagamento, etc.
module PatientPortal
  class SendPushJob < ApplicationJob
    queue_as :default
    discard_on ActiveRecord::RecordNotFound

    def perform(notification_id)
      notif = PatientPortalNotification.find(notification_id)

      PatientPortal::PushNotifier.new(patient: notif.patient).deliver!(
        title:   notif.title,
        body:    notif.body,
        payload: (notif.payload || {}).merge(
          kind:           notif.kind,
          notification_id: notif.id
        )
      )
    end
  end
end
