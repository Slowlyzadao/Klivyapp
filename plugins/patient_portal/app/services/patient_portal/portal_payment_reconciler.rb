# Reconcilia eventos de gateway externo (Asaas) com PortalPayment iniciados
# pelo paciente no portal (Sprint G).
#
# Fluxo:
#   1. Paciente clica "Pagar online" → POST /payments cria PortalPayment +
#      cobrança no gateway, status=`awaiting_payment`.
#   2. Paciente paga (PIX/boleto/cartão).
#   3. Asaas dispara webhook `PAYMENT_CONFIRMED` ou `PAYMENT_RECEIVED`.
#   4. `Financial::Webhooks::ProcessAsaasEventJob` chama este reconciler **antes**
#      do fluxo de Installment, porque PortalPayment carrega o método real
#      escolhido pelo paciente.
#   5. Reconciler marca PortalPayment como paid → dispara `PaymentReceiptIssuer`
#      (mesmo service usado pelo `simulate_paid` em dev).
#
# Idempotente: chamar 2x não duplica recibo nem notification.
module PatientPortal
  class PortalPaymentReconciler
    EVENT_PAID = %w[PAYMENT_CONFIRMED PAYMENT_RECEIVED].freeze

    Result = Struct.new(:reconciled, :payment, :reason, keyword_init: true) do
      def reconciled?       = !!reconciled
      def to_h
        { reconciled: reconciled?, payment_id: payment&.id, reason: reason }
      end
    end

    def initialize(event_type:, payload:)
      @event_type = event_type.to_s
      @payload    = payload || {}
    end

    def call
      return Result.new(reconciled: false, reason: 'event_not_payment_paid') unless EVENT_PAID.include?(@event_type)

      payment = locate_portal_payment
      return Result.new(reconciled: false, reason: 'portal_payment_not_found') unless payment

      if payment.paid?
        return Result.new(reconciled: true, payment: payment, reason: 'already_paid')
      end

      paid_at = parse_paid_at
      payment.mark_paid!(at: paid_at, payload: { asaas_event: @event_type, raw: @payload })
      PatientPortal::PaymentReceiptIssuer.new(payment: payment.reload).call

      Result.new(reconciled: true, payment: payment.reload)
    rescue StandardError => e
      Rails.logger.error("[PortalPaymentReconciler] #{e.class} #{e.message}")
      Result.new(reconciled: false, reason: "error: #{e.class}")
    end

    private

    def locate_portal_payment
      gateway_id = payment_gateway_id
      return nil if gateway_id.blank?

      PortalPayment.find_by(gateway_payment_id: gateway_id)
    end

    def payment_gateway_id
      @payload.dig('payment', 'id') || @payload['id']
    end

    def parse_paid_at
      raw = @payload.dig('payment', 'paymentDate') ||
            @payload.dig('payment', 'creditDate') ||
            @payload['paymentDate']
      Time.parse(raw.to_s)
    rescue ArgumentError, TypeError
      Time.current
    end
  end
end
