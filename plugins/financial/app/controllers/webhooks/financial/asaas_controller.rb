module Webhooks
  module Financial
    # Recebe webhooks do Asaas. Endpoint público (sem autenticação Klivy)
    # mas verificado por assinatura (asaas-access-token header) contra
    # GatewaySetting.webhook_secret da conta correspondente.
    #
    # POST /webhooks/financial/asaas?account_id=:id
    # Header: asaas-access-token: <token configurado no painel Asaas>
    #
    # O processamento real é assíncrono (job) — webhook só persiste o evento
    # e responde 200 OK rápido. O job atualiza Installment/PaymentReceipt/Entry.
    #
    # Auditoria 2026-05-22 (`CRIT-SEC-02`): antes retornava 404 quando
    # account não existia e 403 quando setting não existia — distinguia
    # via timing/code, permitindo enumeração de accounts. Agora SEMPRE 403
    # quando qualquer pré-condição falha (account inexistente, setting
    # ausente, webhook_secret vazio, HMAC inválido). Atacante não consegue
    # distinguir "account não existe" de "account existe mas HMAC errado".
    class AsaasController < ActionController::API
      def receive
        # Single lookup combinando account + setting. Se qualquer parte falhar,
        # retorna mesmo 403 (constant-response, sem leak por código diferente).
        account_id = params[:account_id].to_i
        return head(:forbidden) if account_id.zero?

        # JOIN implícito: setting tem FK pra account (account_id NOT NULL).
        # Se setting existe → account existe (mesma query, mesma latência).
        setting = ::Financial::GatewaySetting.find_by(account_id: account_id, gateway: 'asaas')
        return head(:forbidden) unless setting&.webhook_secret&.present?

        account = setting.account
        return head(:forbidden) unless account

        adapter = ::Financial::Gateways::Asaas.new(account: account, setting: setting)
        return head(:forbidden) unless adapter.verify_webhook(headers: request.headers, body: request.raw_post)

        # A partir daqui, request está autenticado — operação normal.
        event = adapter.parse_webhook(headers: request.headers, body: request.raw_post)

        record = persist_event(account, event)
        unless record
          # Evento já visto antes → idempotência (CRIT-SEC mitigation: replay protection).
          return render json: { ok: true, status: 'duplicate' }, status: :ok
        end

        # Marca último webhook recebido para health check.
        setting.update_columns(
          webhook_last_received_at: Time.current,
          webhook_verified: true,
          updated_at: Time.current
        )

        # Processa em background.
        if defined?(::Financial::Webhooks::ProcessAsaasEventJob)
          ::Financial::Webhooks::ProcessAsaasEventJob.perform_later(record.id)
        end

        render json: { ok: true, event_id: event.id }, status: :ok
      rescue StandardError => e
        Rails.logger.error("[Webhooks::Financial::AsaasController] #{e.class} #{e.message}")
        # Não vazar mensagem de erro — 500 genérico.
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
