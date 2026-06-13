# frozen_string_literal: true

module Signatures
  # Job assíncrono que finaliza o ciclo de uma SignatureRequest após o signer
  # ter concluído a assinatura no provider externo. Disparado pelo webhook
  # do provider (Webhooks::ClicksignController#process_payload com event
  # `envelope.completed`) ou manualmente via reconciliação.
  #
  # Pipeline:
  #   1. Carrega SignatureRequest pelo ID.
  #   2. Resolve o Provider correto (mock/clicksign/...) via ProviderResolver.
  #   3. Chama provider.download_signed_pdf — bytes do PDF assinado.
  #   4. Calcula signed_pdf_hash (SHA-256) e atualiza no model.
  #   5. Substitui o file attachment do signable (Document) pelo PDF assinado.
  #      Pra ConsentRecord (que não tem :file), guarda em rendered_html só
  #      atualiza integrity_hash — o PDF é regerado quando necessário.
  #   6. Marca SignatureRequest como `completed`.
  #
  # Agnostic de provider — qualquer provider que implemente
  # `download_signed_pdf` funciona aqui sem mudança.
  class DownloadSignedPdfJob < ApplicationJob
    queue_as :default

    retry_on Signatures::ProviderError, wait: :exponentially_longer, attempts: 5
    retry_on StandardError, wait: 30.seconds, attempts: 3

    def perform(signature_request_id)
      request = SignatureRequest.find(signature_request_id)
      return if request.completed? # idempotente — webhook duplicado é seguro

      unless request.signed?
        Rails.logger.warn("[DownloadSignedPdfJob] request=#{request.id} status=#{request.status} (esperado signed) — pulando")
        return
      end

      # ActiveStorage escopa o blob por tenant via Current.account (ver
      # config/initializers/active_storage_account_scoping.rb). Em job
      # assíncrono Current.account está nil → setamos pro tenant do request
      # pra o PDF assinado cair no prefixo accounts/<id>/ correto.
      Current.account = request.account

      pdf_bytes = fetch_pdf(request)
      signed_hash = Digest::SHA256.hexdigest(pdf_bytes)

      ApplicationRecord.transaction do
        attach_to_signable(request, pdf_bytes)
        request.update!(signed_pdf_hash: signed_hash)
        request.mark_completed!(meta: { signed_pdf_bytes: pdf_bytes.bytesize,
                                        signed_pdf_hash: signed_hash })
      end

      broadcast_completion(request)
    ensure
      Current.account = nil
    end

    private

    def fetch_pdf(request)
      provider = Signatures::ProviderResolver.for_name(request.provider)
      provider.download_signed_pdf(request: request)
    end

    # Document tem has_one_attached :file — substituímos o PDF original
    # pelo assinado. ConsentRecord não tem file attachment (legado guarda
    # texto em body); aí só persistimos o hash, e o PDF assinado pode ser
    # baixado on-demand do provider quando o user clicar "Baixar".
    def attach_to_signable(request, pdf_bytes)
      signable = request.signable
      return unless signable.respond_to?(:file)

      signable.file.attach(
        io: StringIO.new(pdf_bytes),
        filename: signed_filename(request),
        content_type: 'application/pdf'
      )
    end

    def signed_filename(request)
      signable = request.signable
      slug = if signable.respond_to?(:document_type)
               signable.document_type.to_s.parameterize
             else
               signable.class.name.underscore
             end
      "#{slug}-signed-#{request.id}.pdf"
    end

    # Notifica frontend (clínica + portal paciente) que o documento foi
    # assinado. Reutiliza o padrão ActionCable já usado em telemed.
    def broadcast_completion(request)
      return unless defined?(ActionCable)

      ActionCable.server.broadcast(
        "account_#{request.account_id}",
        type: 'signature_request_completed',
        signature_request_id: request.id,
        signable_type: request.signable_type,
        signable_id: request.signable_id
      )
    rescue StandardError => e
      Rails.logger.warn("[DownloadSignedPdfJob] broadcast falhou: #{e.message}")
    end
  end
end
