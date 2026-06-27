# Dispara Web Push para todas as subscriptions ativas do paciente (Sprint G).
#
# Idempotência: o `endpoint` é único por device; subscriptions duplicadas são
# evitadas via uniqueness no schema. Falhas com status 404/410 (subscription
# morta) marcam o registro como disabled — não falha o fluxo de negócio.
#
# Uso típico (já wired em NotificationDispatcher):
#   PatientPortal::PushNotifier.new(patient: p).deliver!(
#     title: 'Pagamento confirmado',
#     body: 'Sua parcela foi paga.',
#     payload: { kind: 'financial_charge', url: '/financial' }
#   )
module PatientPortal
  class PushNotifier
    TTL_SECONDS = 24 * 60 * 60 # 24h — push services descartam após esse tempo

    def initialize(patient:)
      @patient = patient
    end

    # @return [Hash] { delivered: Integer, failed: Integer, disabled: Integer }
    def deliver!(title:, body: nil, payload: {})
      stats = { delivered: 0, failed: 0, disabled: 0 }
      subscriptions = PatientPortalPushSubscription.active.for_patient(@patient)
      return stats if subscriptions.empty?

      message = build_message(title: title, body: body, payload: payload)

      subscriptions.each do |sub|
        send_to(sub, message, stats)
      end

      stats
    end

    private

    def build_message(title:, body:, payload:)
      {
        title: title.to_s,
        body:  body.to_s,
        data:  payload.is_a?(Hash) ? payload : {}
      }.to_json
    end

    def send_to(sub, message, stats)
      WebPush.payload_send(
        message:        message,
        endpoint:       sub.endpoint,
        p256dh:         sub.p256dh_key,
        auth:           sub.auth_key,
        vapid: {
          subject:     VapidKeys.subject,
          public_key:  VapidKeys.public_key,
          private_key: VapidKeys.private_key
        },
        ttl: TTL_SECONDS
      )
      sub.record_success!
      stats[:delivered] += 1
    rescue WebPush::InvalidSubscription, WebPush::ExpiredSubscription
      sub.record_failure!(permanent: true)
      stats[:disabled] += 1
    rescue WebPush::ResponseError, StandardError => e
      Rails.logger.warn("[PushNotifier] falhou para sub=#{sub.id}: #{e.class} #{e.message}")
      sub.record_failure!
      stats[:failed]  += 1
      stats[:disabled] += 1 if sub.reload.disabled?
    end
  end
end
