module Financial
  module Gateways
    # Interface comum de adapter de gateway de pagamento.
    # Todo método deve retornar Financial::Gateways::Result.
    #
    # Adapters concretos:
    #   - Financial::Gateways::Manual  — registra direto, sem chamada externa
    #   - Financial::Gateways::Asaas   — fala com a API do Asaas (skeleton)
    #
    # Modelo conceitual:
    #   - Customer  → vincula paciente a um cliente externo do gateway
    #   - Charge    → representa cobrança (1 instalment ou 1 receipt)
    #   - Webhook   → notificação externa de mudança de status
    class Base
      attr_reader :account, :setting

      def initialize(account:, setting: nil)
        @account = account
        @setting = setting
      end

      # ------------------------------------------------------
      # Customer (paciente ↔ cliente externo do gateway)
      # ------------------------------------------------------

      # Garante que o paciente tem cliente correspondente no gateway.
      # @param patient [Patient]
      # @return [Result]
      def ensure_customer(patient:)
        not_implemented!(__method__)
      end

      # ------------------------------------------------------
      # Charges (cobranças)
      # ------------------------------------------------------

      # Cria uma cobrança no gateway para uma parcela específica.
      # @param installment [Financial::Installment]
      # @param patient     [Patient]
      # @param payment_method [String] dinheiro|pix|debito|credito|boleto
      # @return [Result] payload contém gateway_id, payment_link, barcode_line, pix_qr_code
      def create_charge(installment:, patient:, payment_method:)
        not_implemented!(__method__)
      end

      # Cancela uma cobrança no gateway (parcela ainda não paga).
      def cancel_charge(installment:)
        not_implemented!(__method__)
      end

      # Estorna uma cobrança paga (cria refund).
      def refund_charge(installment:, amount_cents: nil)
        not_implemented!(__method__)
      end

      # Busca status atual de uma cobrança no gateway (sync).
      def fetch_charge(gateway_id:)
        not_implemented!(__method__)
      end

      # ------------------------------------------------------
      # Webhooks
      # ------------------------------------------------------

      # Verifica assinatura do webhook (HMAC do gateway).
      # @return [Boolean]
      def verify_webhook(headers:, body:)
        false
      end

      # Normaliza o payload do webhook em um Event.
      # @return [Event]
      def parse_webhook(headers:, body:)
        not_implemented!(__method__)
      end

      # ------------------------------------------------------
      # Identidade
      # ------------------------------------------------------

      def name
        self.class.name.demodulize.downcase
      end

      def manual?
        name == 'manual'
      end

      private

      def not_implemented!(method)
        raise Financial::Gateways::NotImplementedError,
              "#{self.class.name}##{method} not implemented"
      end
    end

    # Resultado padronizado de qualquer chamada ao gateway.
    class Result
      attr_reader :ok, :data, :error

      def initialize(ok:, data: {}, error: nil)
        @ok = ok
        @data = data
        @error = error
      end

      def ok? = @ok
      def failed? = !@ok

      def self.success(**data) = new(ok: true, data: data)
      def self.failure(message, code: nil, payload: nil)
        new(ok: false, error: Financial::Gateways::GatewayError.new(message, code: code, payload: payload))
      end
    end

    # Evento normalizado de webhook.
    Event = Struct.new(:gateway, :id, :type, :charge_gateway_id, :status, :received_at, :payload, keyword_init: true)
  end
end
