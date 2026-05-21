module Webhooks
  module Financial
    # Recebe webhooks do Asaas. Endpoint público (sem autenticação Klivy)
    # mas verificado por assinatura (asaas-access-token header) contra
    # GatewaySetting.webhook_secret da conta correspondente.
    #
    # POST /webhooks/financial/asaas?account_id=:id
    # Header: asaas-access-token: <token configurado no painel Asaas>
    #
    # O processamento real é assíncrono (job) — webhook só persiste o evento e
    # responde 200 OK rápido. O job atualiza Installment/PaymentReceipt/Entry
    # conforme o evento.
    class AsaasController < ActionController::API
      def receive
        account = ::Account.find_by(id: params[:account_id])
        return head :not_found unless account

        setting = ::Financial::GatewaySetting.find_by(account_id: account.id, gateway: 'asaas')
        return head :forbidden unless setting

        adapter = ::Financial::Gateways::Asaas.new(account: account, setting: setting)
        unless adapter.verify_webhook(headers: request.headers, body: request.raw_post)
          return head :unauthorized
        end

        event = adapter.parse_webhook(headers: request.headers, body: request.raw_post)

        record = persist_event(account, event)
        unless record
          # Evento já visto antes → idempotência
          return render json: { ok: true, status: 'duplicate' }, status: :ok
        end

        # Marca último webhook recebido para health check.
        setting.update_columns(webhook_last_received_at: Time.current, webhook_verified: true, updated_at: Time.current)

        # Processa em background.
        if defined?(::Financial::Webhooks::ProcessAsaasEventJob)
          ::Financial::Webhooks::ProcessAsaasEventJob.perform_later(record.id)
        end

        render json: { ok: true, event_id: event.id }, status: :ok
      rescue StandardError => e
        Rails.logger.error("[Webhooks::Financial::AsaasController] #{e.class} #{e.message}")
        head :internal_server_error
      end

      private

      def persist_event(account, event)
        ::Financial::GatewayWebhookEvent.create!(
          account_id: account.id,
          gateway: 'asaas',
          event_id: event.id || SecureRandom.uuid,
          event_type: event.type,
          status: 'received',
          payload: event.payload || {},
          received_at: event.received_at || Time.current
        )
      rescue ActiveRecord::RecordNotUnique
        nil
      end
    end
  end
end
