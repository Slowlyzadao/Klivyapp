module Financial
  module Webhooks
    # Processa um webhook event do Asaas em background.
    # Mapeia eventos para mudanças de status no domínio interno.
    # Canon (referência Asaas): https://docs.asaas.com/reference/eventos
    #
    # Refatorado 2026-05-22 (Fase 3) — corrige `CRIT-SVC-03` e `CRIT-SVC-04`:
    #
    # CRIT-SVC-03: ANTES, `handle_payment_received` chamava `ReceivePayment`
    # com `received_at: Date.current`. Asaas envia webhooks em retry — se o
    # pagamento ocorreu em 15/jan mas o webhook chegou em 17/jan, registrava
    # competence_date/cash_date errado. Agora extrai `paid_date` do payload
    # (`payment.paymentDate`) e usa como `received_at`; fallback pra
    # `Date.current` SÓ se ausente/inválido.
    #
    # CRIT-SVC-04: Antes, `rescue StandardError` re-raise sempre — Sidekiq
    # retentava indefinidamente mesmo em erros estruturais (ex: parcela
    # cancelada). Agora distingue:
    #   - Erros transientes (rede, timeout, deadlock) → re-raise pra retry
    #   - Erros estruturais (validation, not_found) → mark_failed! e desiste
    class ProcessAsaasEventJob < ApplicationJob
      queue_as :default

      # Erros que Sidekiq deve retentar (transient)
      TRANSIENT_ERRORS = [
        ActiveRecord::Deadlocked,
        ActiveRecord::LockWaitTimeout,
        ActiveRecord::ConnectionNotEstablished,
        Net::ReadTimeout,
        Net::OpenTimeout,
        Errno::ECONNRESET,
        Errno::ECONNREFUSED
      ].freeze

      retry_on(*TRANSIENT_ERRORS, wait: :polynomially_longer, attempts: 5)
      discard_on ActiveJob::DeserializationError

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

        handler = EVENT_HANDLERS[event.event_type]
        if handler
          result = send(handler, event)
          # Handlers retornam ServiceResult OU nil (compat). Se nil, assume sucesso (compat).
          if result.respond_to?(:failure?) && result.failure?
            event.mark_failed!("handler #{handler} retornou failure: #{result.errors.join('; ')}")
          else
            event.mark_processed!
          end
        else
          event.mark_ignored!("event_type sem handler: #{event.event_type}")
        end
      rescue *TRANSIENT_ERRORS => e
        # Transientes — re-raise pra Sidekiq retentar.
        event&.mark_failed!("transient: #{e.class.name}: #{e.message}")
        raise
      rescue StandardError => e
        # Estruturais — marca como falhado e NÃO re-raise (sem retry).
        # Operador vê event.failure_reason e investiga manualmente.
        # Auditoria `CRIT-SVC-04`: antes essas situações geravam loop de retry
        # infinito porque o rescue sempre re-raise.
        event&.mark_failed!("structural: #{e.class.name}: #{e.message}")
        Rails.logger.error("[ProcessAsaasEventJob] structural failure event=#{event_id}: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}")
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

      # Auditoria `CRIT-SVC-03`: usar paid_date do payload, não Date.current.
      # Asaas envia data no formato "YYYY-MM-DD" em `payment.paymentDate`.
      def extract_paid_date(payload)
        raw = payload.dig('payment', 'paymentDate') ||
              payload['paymentDate'] ||
              payload.dig('payment', 'effectiveDate') ||
              payload['effectiveDate']
        return Date.current if raw.blank?

        Date.parse(raw.to_s)
      rescue ArgumentError, TypeError
        Rails.logger.warn("[ProcessAsaasEventJob] paid_date inválido: '#{raw}', fallback pra Date.current")
        Date.current
      end

      def handle_payment_received(event)
        inst = find_installment(event.payload)
        return event.mark_ignored!('installment não encontrado') unless inst

        bank = inst.budget.account.financial_bank_accounts.find_by(kind: 'checking') if inst.respond_to?(:budget)
        bank ||= Financial::BankAccount.for_account(inst.account_id).where(kind: 'checking').first
        return event.mark_ignored!('conta destino não configurada') unless bank

        paid_date = extract_paid_date(event.payload)

        Financial::ReceivePayment.call(
          account: inst.budget.account,
          actor: nil,
          bank_account: bank,
          installment_amounts: [{ installment_id: inst.id, amount_cents: inst.remaining_cents }],
          payment_method: inst.payment_method,
          received_at: paid_date,
          notes: "[Asaas webhook] event_id=#{event.event_id} paid_date=#{paid_date}"
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
