# frozen_string_literal: true

module Signatures
  module Providers
    # Provider falso pra dev e testes — não faz HTTP. Simula um envelope
    # gerando ID fake `mock_<random>`. Útil pra:
    #   - testes E2E sem rede
    #   - desenvolvimento local sem credenciais Clicksign
    #   - ambiente de staging onde clínicas-piloto podem testar o fluxo
    #     sem riscos de cobrança
    #
    # `signing_url` retornado aponta pra uma rota interna do app que
    # pode renderizar uma página de "assinatura simulada" (a implementar
    # quando necessário). No MVP atual, o fluxo de "assinar" pode ser
    # disparado via runner pra testes.
    class MockProvider < Signatures::Provider
      def create_envelope(request:, pdf_data: nil)
        envelope_id = "mock_#{SecureRandom.hex(8)}"
        signing_url = "/mock/signatures/#{envelope_id}"

        Rails.logger.info("[MockProvider] create envelope=#{envelope_id} request=#{request.id} pdf_bytes=#{pdf_data&.bytesize}")

        Provider::Result.new(
          success?: true,
          external_id: envelope_id,
          signing_url: signing_url,
          data: { simulated: true },
          error: nil
        )
      end

      def cancel_envelope(request:, reason: nil)
        Rails.logger.info("[MockProvider] cancel envelope=#{request.external_id} reason=#{reason}")
        Provider::Result.new(success?: true, data: { reason: reason }, error: nil)
      end

      def resend_envelope(request:)
        Rails.logger.info("[MockProvider] resend envelope=#{request.external_id}")
        Provider::Result.new(success?: true, data: {}, error: nil)
      end

      # Reflete o status corrente — em prod isso bateria no Clicksign.
      def fetch_status(request:)
        Provider::Result.new(
          success?: true,
          data: {
            status: request.status,
            external_id: request.external_id,
            signed_at: request.signed_at
          },
          error: nil
        )
      end

      # Em mock, "PDF assinado" é o mesmo PDF original. Em testes que
      # validam o fluxo de download, atribuímos um conteúdo simulado.
      def download_signed_pdf(request:)
        "%PDF-1.4\n% Mock signed PDF for envelope #{request.external_id}\n%%EOF\n"
      end
    end
  end
end
