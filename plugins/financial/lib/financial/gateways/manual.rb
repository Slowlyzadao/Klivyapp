module Financial
  module Gateways
    # Adapter "manual" — não fala com nenhuma API externa.
    # É o default antes da clínica conectar Asaas. O dinheiro é considerado
    # registrado na hora pelo operador (recepção dá baixa direto).
    class Manual < Base
      def ensure_customer(patient:)
        Result.success(gateway_customer_id: nil)
      end

      def create_charge(installment:, patient:, payment_method:)
        # Não há cobrança remota; só marca o registro como manual.
        Result.success(
          gateway_id: nil,
          gateway_status: 'manual',
          payment_link: nil,
          barcode_line: nil,
          pix_qr_code: nil,
          pix_qr_code_image_url: nil
        )
      end

      def cancel_charge(installment:)
        Result.success(gateway_status: 'canceled')
      end

      def refund_charge(installment:, amount_cents: nil)
        Result.success(gateway_status: 'refunded', amount_cents: amount_cents)
      end

      def fetch_charge(gateway_id:)
        Result.success(gateway_status: 'manual', payload: {})
      end

      def verify_webhook(headers:, body:)
        # Manual não processa webhooks externos.
        false
      end

      def parse_webhook(headers:, body:)
        raise Financial::Gateways::NotImplementedError, 'Manual gateway does not receive webhooks'
      end
    end
  end
end
