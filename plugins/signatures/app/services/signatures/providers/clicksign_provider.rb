# frozen_string_literal: true

module Signatures
  module Providers
    # Provider Clicksign — implementação real via HTTP API v3.
    #
    # **Sessão atual: skeleton com TODOs.** A integração HTTP completa entra
    # na próxima sessão, quando user passar:
    #   - `CLICKSIGN_API_TOKEN`
    #   - `CLICKSIGN_BASE_URL` (default https://app.clicksign.com pra prod;
    #     https://sandbox.clicksign.com pra sandbox)
    #   - `CLICKSIGN_WEBHOOK_SECRET` pra validar HMAC dos webhooks
    #
    # Pra desenvolvimento atual, use `MockProvider` (default em dev/test).
    # Em prod, troca via ENV `SIGNATURES_PROVIDER=clicksign`.
    #
    # Referências:
    #   - https://developers.clicksign.com/reference (API v3)
    #   - https://developers.clicksign.com/docs/webhooks
    class ClicksignProvider < Signatures::Provider
      DEFAULT_BASE_URL = 'https://app.clicksign.com'

      def initialize(api_token: nil, base_url: nil)
        @api_token = api_token || ENV.fetch('CLICKSIGN_API_TOKEN', nil)
        @base_url  = base_url  || ENV.fetch('CLICKSIGN_BASE_URL', DEFAULT_BASE_URL)
        raise ProviderError, 'CLICKSIGN_API_TOKEN ausente' if @api_token.blank?
      end

      # TODO (próxima sessão):
      # 1. POST {base_url}/api/v3/envelopes — cria envelope com signer
      #    {name, email, communicate_by: 'email'|'whatsapp'|'sms'}
      # 2. POST {base_url}/api/v3/envelopes/{id}/documents — upload do PDF
      # 3. POST {base_url}/api/v3/envelopes/{id}/notifications — dispara
      #    convite ao signer (retorna signing_url)
      def create_envelope(request:, pdf_data:)
        raise NotImplementedError, 'ClicksignProvider#create_envelope — implementar na próxima sessão'
      end

      # TODO: DELETE {base_url}/api/v3/envelopes/{external_id}
      def cancel_envelope(request:, reason: nil)
        raise NotImplementedError, 'ClicksignProvider#cancel_envelope — implementar na próxima sessão'
      end

      # TODO: POST {base_url}/api/v3/envelopes/{external_id}/notifications
      def resend_envelope(request:)
        raise NotImplementedError, 'ClicksignProvider#resend_envelope — implementar na próxima sessão'
      end

      # TODO: GET {base_url}/api/v3/envelopes/{external_id}
      def fetch_status(request:)
        raise NotImplementedError, 'ClicksignProvider#fetch_status — implementar na próxima sessão'
      end

      # TODO: GET {base_url}/api/v3/envelopes/{external_id}/documents/{id}
      # → segue redirect pra blob signed → baixa bytes
      def download_signed_pdf(request:)
        raise NotImplementedError, 'ClicksignProvider#download_signed_pdf — implementar na próxima sessão'
      end

      private

      attr_reader :api_token, :base_url

      # Sugestão de skeleton pro HTTP client (Faraday ou Net::HTTP), pra
      # implementar depois:
      #
      #   def http
      #     @http ||= Faraday.new(url: base_url) do |c|
      #       c.request :json
      #       c.response :json, content_type: /\bjson$/
      #       c.headers['Authorization'] = "Bearer #{api_token}"
      #       c.headers['Accept'] = 'application/json'
      #     end
      #   end
    end
  end
end
