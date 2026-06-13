# Gateway fake usado em dev e em CI. Gera QR codes/linhas digitáveis
# determinísticas baseadas no ID da parcela — permite testar o fluxo do
# paciente do início ao fim sem credenciais externas, e permite testar
# "pagamento confirmado" via endpoint dev-only `POST /payments/:id/simulate_paid`.
#
# IMPORTANTE: NÃO usar em produção. `Gateway.for(account:)` escolhe Asaas
# automaticamente quando `Rails.env.production?` e há config.
module PatientPortal
  module Payment
    class MockGateway < Gateway
      def create_charge!(method:, amount_cents:, patient:, installment:)
        token = SecureRandom.hex(8)

        Result.new(
          gateway_payment_id: "mock_#{token}",
          pix_qr_code:        method == 'pix'    ? fake_pix_qr(token, amount_cents) : nil,
          pix_copy_paste:     method == 'pix'    ? fake_pix_copy_paste(token, amount_cents) : nil,
          boleto_url:         method == 'boleto' ? fake_boleto_url(token) : nil,
          boleto_barcode:     method == 'boleto' ? fake_boleto_barcode(amount_cents) : nil,
          expires_at:         expiration_for(method),
          raw: {
            simulated: true,
            method: method,
            installment_id: installment.id,
            patient_id: patient.id
          }
        )
      end

      private

      def fake_pix_qr(token, amount_cents)
        # Retorna um payload "BR Code" minimal — apenas pra renderizar como
        # QR no front (qrcode.vue ou data-uri). Front usa um lib client-side
        # pra desenhar a partir desse string.
        amount = format('%.2f', amount_cents / 100.0)
        "00020126#{token}5204000053039865802BR5910Klivy Test6009Sao Paulo62#{token[0..3]}54#{amount.length.to_s.rjust(2, '0')}#{amount}6304ABCD"
      end

      def fake_pix_copy_paste(token, amount_cents)
        fake_pix_qr(token, amount_cents)
      end

      def fake_boleto_url(token)
        "https://klivy.test/boleto/mock_#{token}.pdf"
      end

      def fake_boleto_barcode(amount_cents)
        # Linha digitável padrão (47 dígitos sem espaços) baseada no valor.
        amount = amount_cents.to_s.rjust(10, '0')
        "23793#{amount[0..4]} 38128#{amount[5..9]} 23456 7 8901234567890"
      end

      def expiration_for(method)
        case method
        when 'pix'    then 30.minutes.from_now
        when 'boleto' then 3.days.from_now
        else 24.hours.from_now
        end
      end
    end
  end
end
