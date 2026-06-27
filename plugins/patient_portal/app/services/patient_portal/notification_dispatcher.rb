# Cria notificações in-app de forma idempotente. Chamado dos fluxos das
# Sprints C/D/E/F sempre que algo relevante acontece — confirmation de
# agendamento, novo documento, consent assinado, pagamento confirmado, etc.
#
# Sprint G: além de persistir a notificação in-app, dispara Web Push em
# background (ActiveJob) para subscriptions ativas do paciente. Web push
# nunca quebra o fluxo de negócio — falha silenciosa.
#
# Não falha o fluxo de negócio se notif quebrar (rescue StandardError).
module PatientPortal
  class NotificationDispatcher
    def self.dispatch(account:, patient:, kind:, title:, body: nil, payload: {})
      notif = PatientPortalNotification.create!(
        account: account, patient: patient,
        kind: kind, title: title, body: body, payload: payload
      )

      enqueue_push(notif)
      notif
    rescue StandardError => e
      Rails.logger.error("[NotificationDispatcher] falhou: #{e.message}")
      nil
    end

    def self.enqueue_push(notif)
      return unless defined?(PatientPortal::SendPushJob)

      PatientPortal::SendPushJob.perform_later(notif.id)
    rescue StandardError => e
      Rails.logger.warn("[NotificationDispatcher] push enqueue falhou: #{e.message}")
    end
  end
end
