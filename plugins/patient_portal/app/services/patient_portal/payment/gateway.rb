# Interface dos gateways de pagamento. Implementações concretas devem
# responder a `create_charge!(...)` retornando um Result.
#
# Manter essa interface pequena é deliberado — só o que o portal precisa.
# Webhook handling fica no controller do plugin financial (já existe pra
# Asaas), que reconcilia disparando `PortalPaymentReconciler`.
module PatientPortal
  module Payment
    class Gateway
      Result = Struct.new(
        :gateway_payment_id, :pix_qr_code, :pix_copy_paste,
        :boleto_url, :boleto_barcode, :expires_at, :raw,
        keyword_init: true
      ) do
        def to_attrs
          {
            gateway_payment_id: gateway_payment_id,
            pix_qr_code:        pix_qr_code,
            pix_copy_paste:     pix_copy_paste,
            boleto_url:         boleto_url,
            boleto_barcode:     boleto_barcode,
            expires_at:         expires_at,
            gateway_payload:    raw || {}
          }.compact
        end
      end

      # Subclasses sobrescrevem.
      # @param method [String] 'pix' | 'boleto' | 'credit_card'
      # @param amount_cents [Integer]
      # @param patient [Patient]
      # @param installment [Financial::Installment]
      # @return [Result]
      def create_charge!(method:, amount_cents:, patient:, installment:)
        raise NotImplementedError
      end

      # Factory — escolhe implementação concreta com base na config.
      # Em dev sem credencial: MockGateway (gera QR fake + permite "simular pagamento").
      # Em prod com config: AsaasGateway (vai pelo gateway real, webhook reconcilia).
      def self.for(account:)
        setting = account.financial_gateway_settings.find_by(active: true) if account.respond_to?(:financial_gateway_settings)
        kind = setting&.gateway || (Rails.env.production? ? 'asaas' : 'mock')

        case kind
        when 'asaas' then AsaasGateway.new(setting: setting)
        else              MockGateway.new
        end
      rescue StandardError
        MockGateway.new
      end
    end
  end
end
