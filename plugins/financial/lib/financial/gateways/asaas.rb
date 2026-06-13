module Financial
  module Gateways
    # Adapter Asaas — skeleton.
    # Estrutura completa para integração futura. Os métodos retornam Result.failure
    # com mensagem clara enquanto a integração não está plugada — assim o sistema
    # detecta no boot que falta wiring, em vez de explodir em runtime no meio de um
    # fluxo de cobrança.
    #
    # Para ativar:
    #   1. Cadastrar API key da clínica em Financial::GatewaySetting (api_key_ciphertext).
    #   2. Configurar webhook no Asaas apontando para POST /webhooks/financial/asaas
    #      (ver Financial::WebhooksController).
    #   3. Implementar os TODOs abaixo. Cada método tem o endpoint correspondente
    #      da API Asaas no comentário.
    #
    # Referência: https://docs.asaas.com/reference/comece-por-aqui
    class Asaas < Base
      BASE_URL_PRODUCTION = 'https://api.asaas.com/v3'.freeze
      BASE_URL_SANDBOX    = 'https://api-sandbox.asaas.com/v3'.freeze

      WEBHOOK_SIGNATURE_HEADER = 'asaas-access-token'.freeze

      def base_url
        setting&.environment == 'production' ? BASE_URL_PRODUCTION : BASE_URL_SANDBOX
      end

      def api_key
        @api_key ||= setting&.api_key
      end

      # POST /customers — cria ou atualiza cliente (paciente).
      def ensure_customer(patient:)
        # TODO(asaas): chamar POST /customers se patient não tem gateway_customer_id.
        # Reutilizar gateway_customer_id armazenado em Patient.metadata['asaas_customer_id'].
        # Retornar Result.success(gateway_customer_id: id_externo).
        Result.failure(
          'Asaas adapter not wired (ensure_customer)',
          code: 'not_wired'
        )
      end

      # POST /payments — cria cobrança avulsa (1 parcela).
      # Mapeamento de payment_method → billingType:
      #   pix      → PIX
      #   boleto   → BOLETO
      #   credito  → CREDIT_CARD
      #   debito   → DEBIT_CARD
      #   dinheiro → UNDEFINED (Asaas não cobra; só registra como cobrança em aberto)
      def create_charge(installment:, patient:, payment_method:)
        # TODO(asaas):
        #   1. Garantir customer (ensure_customer).
        #   2. Montar payload com value, dueDate, billingType, externalReference (installment.id).
        #   3. POST /payments → guardar id, invoiceUrl, bankSlipUrl.
        #   4. Para PIX, GET /payments/:id/pixQrCode para QR code dinâmico.
        #   5. Retornar Result.success(gateway_id:, payment_link:, barcode_line:, pix_qr_code:).
        Result.failure(
          'Asaas adapter not wired (create_charge)',
          code: 'not_wired'
        )
      end

      def cancel_charge(installment:)
        # TODO(asaas): DELETE /payments/:id
        Result.failure('Asaas adapter not wired (cancel_charge)', code: 'not_wired')
      end

      def refund_charge(installment:, amount_cents: nil)
        # TODO(asaas): POST /payments/:id/refund {value: amount}
        Result.failure('Asaas adapter not wired (refund_charge)', code: 'not_wired')
      end

      def fetch_charge(gateway_id:)
        # TODO(asaas): GET /payments/:id
        Result.failure('Asaas adapter not wired (fetch_charge)', code: 'not_wired')
      end

      # Webhook signature: Asaas envia o token configurado no painel via header
      # `asaas-access-token`. Comparar com setting.webhook_secret.
      def verify_webhook(headers:, body:)
        return false unless setting

        expected = setting.webhook_secret
        return false if expected.blank?

        received = headers[WEBHOOK_SIGNATURE_HEADER] ||
                   headers["HTTP_#{WEBHOOK_SIGNATURE_HEADER.upcase.tr('-', '_')}"]
        return false if received.blank?

        ActiveSupport::SecurityUtils.secure_compare(received.to_s, expected.to_s)
      end

      # Eventos relevantes (canon — o que precisa virar mudança de status interno):
      #   PAYMENT_CONFIRMED       → installment.status = recebido (sem boleto liquidado ainda)
      #   PAYMENT_RECEIVED        → installment.status = recebido + cria PaymentReceipt + Entry
      #   PAYMENT_OVERDUE         → installment.status = vencido
      #   PAYMENT_REFUNDED        → installment.status = estornado
      #   PAYMENT_CHARGEBACK_REQUESTED / DISPUTE_LOST → installment.status = estornado
      #   PAYMENT_DELETED         → installment.status = cancelado
      def parse_webhook(headers:, body:)
        json = body.is_a?(String) ? JSON.parse(body) : body
        Event.new(
          gateway: 'asaas',
          id: json['id'] || json.dig('payment', 'id'),
          type: json['event'],
          charge_gateway_id: json.dig('payment', 'id') || json['id'],
          status: json.dig('payment', 'status'),
          received_at: Time.current,
          payload: json
        )
      end
    end
  end
end
