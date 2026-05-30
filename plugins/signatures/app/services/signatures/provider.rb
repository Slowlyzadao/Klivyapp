# frozen_string_literal: true

module Signatures
  # Interface abstrata pra providers de assinatura eletrônica. Cada
  # implementação concreta (ClicksignProvider, MockProvider, etc.) tem que
  # responder a esses métodos. Não usamos herança forte (Ruby duck typing
  # basta) — esse arquivo serve de documentação executável.
  #
  # Convenção de retorno: cada método retorna `Result` ou levanta
  # `Signatures::ProviderError` com mensagem clara.
  class Provider
    Result = Struct.new(:success?, :external_id, :signing_url, :data, :error, keyword_init: true)

    # Cria um envelope no provider externo a partir de uma SignatureRequest
    # já persistida em estado `pending`.
    #
    # @param request [SignatureRequest]
    # @param pdf_data [String] bytes do PDF a ser assinado
    # @return [Result]
    def create_envelope(request:, pdf_data:)
      raise NotImplementedError, "#{self.class} must implement #create_envelope"
    end

    # Cancela um envelope ainda não assinado.
    # @return [Result]
    def cancel_envelope(request:, reason: nil)
      raise NotImplementedError, "#{self.class} must implement #cancel_envelope"
    end

    # Reenvia o convite ao signatário (email/WhatsApp). Não cria novo
    # envelope — só dispara notificação novamente.
    # @return [Result]
    def resend_envelope(request:)
      raise NotImplementedError, "#{self.class} must implement #resend_envelope"
    end

    # Consulta status atual no provider — usado pra reconciliação manual
    # quando suspeitamos que um webhook foi perdido.
    # @return [Result] data inclui { status, signed_pdf_url, viewed_at, ... }
    def fetch_status(request:)
      raise NotImplementedError, "#{self.class} must implement #fetch_status"
    end

    # Baixa o PDF assinado quando `signed`. Caller é responsável por anexar
    # ao Document/ConsentRecord original e calcular signed_pdf_hash.
    # @return [String] bytes do PDF
    def download_signed_pdf(request:)
      raise NotImplementedError, "#{self.class} must implement #download_signed_pdf"
    end
  end

  class ProviderError < StandardError; end
end
