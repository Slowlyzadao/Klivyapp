# frozen_string_literal: true

module Signatures
  # Orquestra: cria SignatureRequest local → chama provider pra criar
  # envelope externo → registra external_id + signing_url → marca como
  # 'sent'.
  #
  # Pipeline:
  #   1. Resolve PDF do signable (Document.file ou render on-demand)
  #   2. Cria SignatureRequest(status: 'pending') localmente
  #   3. Chama provider.create_envelope(request, pdf_data)
  #   4. Se sucesso: SignatureRequest.mark_sent! (external_id, signing_url)
  #   5. Se falha: SignatureRequest.mark_failed!
  #   6. Retorna Result com a request final
  class RequestCreator
    Result = Struct.new(:success?, :request, :error, keyword_init: true)

    def self.call(**args)
      new(**args).run
    end

    def initialize(signable:, requested_by:, signer_name:, signer_email:,
                   signer_phone: nil, signer_cpf: nil, message: nil,
                   provider_name: nil)
      @signable      = signable
      @account       = signable.account
      @requested_by  = requested_by
      @signer_name   = signer_name
      @signer_email  = signer_email
      @signer_phone  = signer_phone
      @signer_cpf    = signer_cpf
      @message       = message
      @provider_name = provider_name || ProviderResolver.default_name
    end

    def run
      pdf_data = extract_pdf_data
      return Result.new(success?: false, error: 'PDF não disponível pro signable') if pdf_data.blank?

      request = build_request(pdf_data)
      request.save!

      provider = ProviderResolver.for_name(@provider_name)
      result = provider.create_envelope(request: request, pdf_data: pdf_data)

      if result.success?
        request.mark_sent!(
          external_id: result.external_id,
          signing_url: result.signing_url,
          meta: {
            provider: @provider_name,
            requested_by_user_id: @requested_by&.id,
            data: result.data
          }
        )
        Result.new(success?: true, request: request, error: nil)
      else
        request.mark_failed!(reason: result.error || 'provider returned failure',
                             meta: { provider: @provider_name })
        Result.new(success?: false, request: request, error: result.error)
      end
    rescue StandardError => e
      Rails.logger.error("[Signatures::RequestCreator] #{e.class}: #{e.message}")
      Result.new(success?: false, error: "#{e.class}: #{e.message}")
    end

    private

    # PDF vem de lugares diferentes dependendo do signable:
    #   - Document: tem has_one_attached :file (Active Storage)
    #   - ConsentRecord: NÃO tem file attachment — precisa renderizar
    #     on-demand a partir de rendered_html. (Já marcado como pendência
    #     em ConsentRecordBuilder.)
    def extract_pdf_data
      if @signable.respond_to?(:file) && @signable.file.attached?
        @signable.file.blob.download
      elsif @signable.respond_to?(:rendered_html) && @signable.rendered_html.present?
        # Re-renderiza via Grover. Em prod, isso seria cacheado.
        Grover.new(@signable.rendered_html, format: 'A4').to_pdf
      end
    end

    def build_request(pdf_data)
      SignatureRequest.new(
        account: @account,
        signable: @signable,
        requested_by_user: @requested_by,
        provider: @provider_name,
        status: 'pending',
        signer_name: @signer_name,
        signer_email: @signer_email,
        signer_phone: @signer_phone,
        signer_cpf: @signer_cpf,
        message: @message,
        original_pdf_hash: Digest::SHA256.hexdigest(pdf_data),
        audit_log: [{
          'at' => Time.current.iso8601,
          'kind' => 'created',
          'meta' => { 'requested_by_user_id' => @requested_by&.id }
        }]
      )
    end
  end
end
