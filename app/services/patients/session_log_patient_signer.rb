# frozen_string_literal: true

# app/services/patients/session_log_patient_signer.rb
#
# Serviço orquestrador de assinatura do PACIENTE numa sessão de evolução.
# Espelha Patients::ConsentSigner — delega ao model conforme o modo
# (local_tablet ou remote_link), anexa imagem da assinatura via Active Storage
# e dispara timeline event assíncrono.
#
# Uso:
#   result = Patients::SessionLogPatientSigner.call(
#     session_log: @log,
#     mode: 'local_tablet',
#     signature_blob: params[:signature],
#     ip_address: request.remote_ip,
#     device_info: request.user_agent,
#     actor: current_user
#   )

module Patients
  class SessionLogPatientSigner
    Result = Struct.new(:success?, :session_log, :error, keyword_init: true)

    def self.call(**args)
      new(**args).call
    end

    def initialize(session_log:, mode:, signature_blob:, ip_address:, device_info: nil, actor: nil)
      @session_log    = session_log
      @mode           = mode
      @signature_blob = signature_blob
      @ip_address     = ip_address
      @device_info    = device_info
      @actor          = actor
    end

    def call
      validate_inputs!

      ActiveRecord::Base.transaction do
        sign_session_log!
        dispatch_timeline_event
      end

      Result.new(success?: true, session_log: @session_log, error: nil)
    rescue StandardError => e
      Rails.logger.error("[SessionLogPatientSigner] Erro ao assinar sessão #{@session_log.id}: #{e.message}")
      Result.new(success?: false, session_log: nil, error: e.message)
    end

    private

    def validate_inputs!
      raise ArgumentError, 'Assinatura é obrigatória.' if @signature_blob.blank?
      raise ArgumentError, 'IP é obrigatório para rastreabilidade.' if @ip_address.blank?
      raise ArgumentError, 'Modo de assinatura inválido.' unless SessionLog::SIGNATURE_MODES.include?(@mode)
      raise StandardError, 'Sessão já foi assinada pelo paciente.' if @session_log.patient_signed?
    end

    def sign_session_log!
      case @mode
      when 'local_tablet'
        @session_log.sign_patient_locally!(
          signature_blob: @signature_blob,
          ip_address: @ip_address,
          device_info: @device_info
        )
      when 'remote_link'
        @session_log.sign_patient_remotely!(
          signature_blob: @signature_blob,
          ip_address: @ip_address,
          device_info: @device_info
        )
      end
      attach_signature_image!
    end

    # Frontend envia base64 data URL (ex.: "data:image/webp;base64,..."). Decodifica
    # e anexa via Active Storage. Falha silenciosa só loga warn — a assinatura
    # canônica já está gravada no campo `patient_signature_blob`.
    def attach_signature_image!
      return if @signature_blob.blank?

      match = @signature_blob.match(/\Adata:([^;]+);base64,(.+)\z/m)
      return unless match

      mime_type = match[1]
      binary    = Base64.decode64(match[2])
      ext       = mime_type.split('/').last

      @session_log.patient_signature_image.attach(
        io: StringIO.new(binary),
        filename: "session_log_signature_#{@session_log.id}.#{ext}",
        content_type: mime_type
      )
    rescue StandardError => e
      Rails.logger.warn("[SessionLogPatientSigner] Falha ao anexar imagem: #{e.message}")
    end

    def dispatch_timeline_event
      Patients::PatientTimelineEventJob.perform_later(
        patient_id: @session_log.patient_id,
        account_id: @session_log.account_id,
        actor_id: @actor&.id,
        event_type: 'session_log_patient_signed',
        resource_type: 'SessionLog',
        resource_id: @session_log.id,
        description: "Paciente assinou a sessão de #{@session_log.performed_at&.strftime('%d/%m/%Y')}",
        metadata: {
          mode: @mode,
          ip_address: @ip_address,
          device_info: @device_info,
          integrity_hash: @session_log.patient_signature_integrity_hash
        }
      )
    end
  end
end
