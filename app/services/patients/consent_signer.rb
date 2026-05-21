# frozen_string_literal: true

# app/services/patients/consent_signer.rb
#
# Serviço orquestrador de assinatura de consentimentos.
# Delega para o model conforme o modo (local ou remoto),
# dispara Timeline event assíncrono e retorna Result struct.
#
# Uso:
#   result = Patients::ConsentSigner.call(
#     consent: @consent,
#     mode: 'local_tablet',
#     signature_blob: params[:signature_blob],
#     ip_address: request.remote_ip,
#     device_info: params[:device_info],
#     actor: current_user
#   )
#
#   if result.success?
#     result.consent   # ConsentRecord atualizado
#   end

module Patients
  class ConsentSigner
    Result = Struct.new(:success?, :consent, :error, keyword_init: true)

    def self.call(**args)
      new(**args).call
    end

    def initialize(consent:, mode:, signature_blob:, ip_address:, device_info: nil, actor: nil)
      @consent       = consent
      @mode          = mode
      @signature_blob = signature_blob
      @ip_address    = ip_address
      @device_info   = device_info
      @actor         = actor
    end

    def call
      validate_inputs!

      ActiveRecord::Base.transaction do
        sign_consent!
        dispatch_timeline_event
      end

      Result.new(success?: true, consent: @consent, error: nil)
    rescue StandardError => e
      Rails.logger.error("[ConsentSigner] Erro ao assinar consentimento #{@consent.id}: #{e.message}")
      Result.new(success?: false, consent: nil, error: e.message)
    end

    private

    def validate_inputs!
      raise ArgumentError, 'Assinatura é obrigatória' if @signature_blob.blank?
      raise ArgumentError, 'IP é obrigatório para rastreabilidade' if @ip_address.blank?
      raise ArgumentError, 'Modo inválido' unless %w[local_tablet remote_link].include?(@mode)
      raise StandardError, 'Consentimento já foi assinado' if @consent.signed?
      raise StandardError, 'Consentimento está vencido ou revogado' if @consent.expired? || @consent.revoked?
    end

    def sign_consent!
      case @mode
      when 'local_tablet'
        @consent.sign_locally!(
          signature_blob: @signature_blob,
          ip_address: @ip_address,
          device_info: @device_info
        )
      when 'remote_link'
        @consent.sign_remotely!(
          signature_blob: @signature_blob,
          ip_address: @ip_address,
          device_info: @device_info
        )
      end
      attach_signature_image!
    end

    # Salva a imagem da assinatura (base64 data URL) via Active Storage.
    # O frontend envia WebP (canvas.toDataURL('image/webp')), o backend decodifica e salva.
    def attach_signature_image!
      return if @signature_blob.blank?

      # Extrai mime_type e dados base64 do data URL
      # Formato: "data:image/webp;base64,<data>" ou "data:image/png;base64,<data>"
      match = @signature_blob.match(/\Adata:([^;]+);base64,(.+)\z/m)
      return unless match

      mime_type = match[1]  # ex: "image/webp" ou "image/png"
      binary    = Base64.decode64(match[2])
      ext       = mime_type.split('/').last  # "webp" ou "png"

      @consent.signature_image.attach(
        io: StringIO.new(binary),
        filename: "signature_#{@consent.id}.#{ext}",
        content_type: mime_type
      )
    rescue StandardError => e
      Rails.logger.warn("[ConsentSigner] Falha ao anexar imagem da assinatura: #{e.message}")
    end

    def dispatch_timeline_event
      Patients::PatientTimelineEventJob.perform_later(
        patient_id: @consent.patient_id,
        account_id: @consent.account_id,
        actor_id: @actor&.id,
        event_type: 'consent_signed',
        resource_type: 'ConsentRecord',
        resource_id: @consent.id,
        description: "Consentimento assinado: #{@consent.title}",
        metadata: {
          mode: @mode,
          ip_address: @ip_address,
          device_info: @device_info,
          integrity_hash: @consent.integrity_hash
        }
      )
    end
  end
end
