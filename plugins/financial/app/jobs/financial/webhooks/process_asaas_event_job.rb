module Financial
  module Webhooks
    # Processa um webhook event do Asaas em background.
    # Mapeia eventos para mudanças de status no domínio interno.
    # Canon (referência Asaas): https://docs.asaas.com/reference/eventos
    class ProcessAsaasEventJob < ApplicationJob
      queue_as :default

      EVENT_HANDLERS = {
        'PAYMENT_CONFIRMED'           => :handle_payment_confirmed,
        'PAYMENT_RECEIVED'            => :handle_payment_received,
        'PAYMENT_OVERDUE'             => :handle_payment_overdue,
        'PAYMENT_REFUNDED'            => :handle_payment_refunded,
        'PAYMENT_CHARGEBACK_REQUESTED' => :handle_payment_refunded,
        'PAYMENT_DELETED'             => :handle_payment_deleted
      }.freeze

      def perform(event_id)
        event = Financial::GatewayWebhookEvent.find(event_id)
        return if event.status != 'received'

        # Sprint G — Cobrança originada no portal do paciente? O reconciler
        # marca PortalPayment e emite recibo via PaymentReceiptIssuer, que já
        # atualiza Installment + Document + Notification. Em caso de match,
        # pulamos o handler legado pra não duplicar trabalho.
        if reconcile_portal_payment?(event)
          rec = PatientPortal::PortalPaymentReconciler.new(
            event_type: event.event_type, payload: event.payload
          ).call
          if rec.reconciled?
            event.mark_processed!
            return
          end
        end

        handler = EVENT_HANDLERS[event.event_type]
        if handler
          send(handler, event)
          event.mark_processed!
        else
          event.mark_ignored!("event_type sem handler: #{event.event_type}")
        end
      rescue StandardError => e
        event&.mark_failed!(e)
        raise
      end

      def reconcile_portal_payment?(event)
        return false unless defined?(PatientPortal::PortalPaymentReconciler)

        PatientPortal::PortalPaymentReconciler::EVENT_PAID.include?(event.event_type)
      end

      private

      def find_installment(payload)
        external_ref = payload.dig('payment', 'externalReference').presence ||
                       payload['externalReference'].presence
        gateway_id = payload.dig('payment', 'id').presence ||
                     payload['id'].presence

        # externalReference setado por nós no create_charge → installment.id
        if external_ref.present?
          inst = Financial::Installment.find_by(id: external_ref.to_i)
          return inst if inst
        end

        Financial::Installment.find_by(gateway_id: gateway_id) if gateway_id.present?
      end

      def handle_payment_received(event)
        inst = find_installment(event.payload)
        return event.mark_ignored!('installment não encontrado') unless inst

        # Cria PaymentReceipt + Entry conforme nosso fluxo via ReceivePayment.
        # Para webhook, assumimos que o valor pago é o total restante.
        bank = inst.budget.account.financial_bank_accounts.find_by(kind: 'checking') if inst.respond_to?(:budget)
        bank ||= Financial::BankAccount.for_account(inst.account_id).where(kind: 'checking').first
        return event.mark_ignored!('conta destino não configurada') unless bank

        Financial::ReceivePayment.call(
          account: inst.budget.account,
          actor: nil,
          bank_account: bank,
          installment_amounts: [{ installment_id: inst.id, amount_cents: inst.remaining_cents }],
          payment_method: inst.payment_method,
          received_at: Date.current,
          notes: "[Asaas webhook] event_id=#{event.event_id}"
        )
      end

      def handle_payment_confirmed(event)
        inst = find_installment(event.payload)
        return unless inst

        inst.update_columns(
          gateway_status: 'CONFIRMED',
          gateway_synced_at: Time.current,
          updated_at: Time.current
        )
      end

      def handle_payment_overdue(event)
        inst = find_installment(event.payload)
        return unless inst
        return if %w[recebido estornado cancelado renegociado].include?(inst.status)

        inst.update!(status: 'vencido')
      end

      def handle_payment_refunded(event)
        inst = find_installment(event.payload)
        return unless inst

        receipt = inst.payment_receipt_items.last&.receipt
        return event.mark_ignored!('parcela ainda não tem receipt') unless receipt

        Financial::RefundPayment.call(
          receipt: receipt,
          actor: nil,
          reason: "[Asaas webhook] event_id=#{event.event_id}",
          refund_via_gateway: false  # já foi reembolsado externamente
        )
      end

      def handle_payment_deleted(event)
        inst = find_installment(event.payload)
        return unless inst
        return if %w[recebido estornado].include?(inst.status)

        inst.update!(status: 'cancelado')
      end
    end
  end
end
