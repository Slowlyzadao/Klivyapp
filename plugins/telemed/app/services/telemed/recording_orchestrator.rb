# Sprint L — Orquestra gravação audio-only do LiveKit Egress.
#
# Estratégia (refinada 2026-05-20):
#   - 3 gravações paralelas durante a consulta:
#     1) ParticipantEgress(doctor)  → doctor-temp.ogg   (deletado pós-transcribe)
#     2) ParticipantEgress(patient) → patient-temp.ogg  (deletado pós-transcribe)
#     3) RoomCompositeEgress         → composite.ogg    (mantido — único permanente)
#   - Whisper × 2 nos temps → diarização perfeita → merge → deleta temps
#   - Storage final permanente: ~28 MB/h (só composite)
#
# Identidades de participantes vêm via `RoomServiceClient.list_participants`
# (LiveKit é fonte da verdade). Todas as 3 chamadas usam `audio_only: true`
# + EncodingOptions com áudio mono opus 64kbps.
require 'livekit'

module Telemed
  class RecordingOrchestrator
    # Format dos arquivos: OGG (codec opus). LiveKit Egress aceita
    # OGG nativo pra audio-only — mais leve que MP4 puro de áudio.
    AUDIO_FILE_TYPE = LiveKit::Proto::EncodedFileType::OGG
    AUDIO_EXT       = 'ogg'.freeze

    # Encoding lean: 64kbps mono opus ≈ 28 MB/h. Suficiente pra Whisper
    # transcrever PT-BR sem perda perceptível.
    AUDIO_BITRATE_BPS = 64_000

    Result = Struct.new(:recording, :started, :skipped_reason, keyword_init: true) do
      def started?       = !!started
      def already_active? = skipped_reason == :already_active
    end

    def initialize(event:, credentials: nil, livekit_client: nil)
      @event       = event
      @account     = event.account
      @credentials = credentials || CredentialsResolver.new(account: @account).call
      @livekit     = livekit_client
    end

    def start!
      return skip(:recording_disabled) unless recording_enabled_for_account?
      return skip(:consent_missing)    unless patient_consented?

      identities = resolve_participant_identities!
      return skip(:participants_not_ready) if identities[:doctor].blank? || identities[:patient].blank?

      # Lock pessimista no event durante check+create — evita 2 calls
      # simultâneos (doctor + patient fazendo `joined` no mesmo tick)
      # criarem 2 recordings duplicados (custo 2x Whisper + Claude).
      # RPCs LiveKit ficam FORA do lock pra não bloquear o DB durante I/O.
      recording = nil
      created = false
      @event.with_lock do
        existing = existing_active_recording
        if existing
          recording = existing
        else
          recording = TelemedRecording.create!(
            agenda_event:   @event,
            account:        @account,
            recording_kind: 'audio',
            status:         'pending'
          )
          created = true
        end
      end

      return skip(:already_active, recording: recording) unless created

      # 3 chamadas paralelas (sequenciais aqui, são fast — só RPC).
      doctor_resp    = start_participant_audio_egress!(identities[:doctor],  role: 'doctor')
      patient_resp   = start_participant_audio_egress!(identities[:patient], role: 'patient')
      composite_resp = start_composite_audio_egress!

      recording.update!(
        doctor_egress_id:    doctor_resp&.egress_id,
        patient_egress_id:   patient_resp&.egress_id,
        composite_egress_id: composite_resp&.egress_id,
        status:              any_started?(doctor_resp, patient_resp, composite_resp) ? 'recording' : 'failed',
        failure_reason:      any_started?(doctor_resp, patient_resp, composite_resp) ? nil : 'Falha ao iniciar Egress'
      )

      Result.new(recording: recording, started: recording.status == 'recording')
    rescue StandardError => e
      Rails.logger.error("[RecordingOrchestrator#start!] event=#{@event.id} #{e.class}: #{e.message}")
      Rails.logger.error(e.backtrace.first(8).join("\n"))
      raise
    end

    # Encerra os 3 jobs. Idempotente — ignora egress já finalizado.
    def stop!(recording)
      return unless recording

      client = egress_client
      recording.expected_egress_ids.each do |egress_id|
        begin
          client.stop_egress(egress_id)
        rescue StandardError => e
          Rails.logger.warn("[RecordingOrchestrator#stop!] egress=#{egress_id} #{e.class}: #{e.message}")
        end
      end
    end

    private

    def any_started?(*responses)
      responses.compact.any?
    end

    def recording_enabled_for_account?
      setting = @account&.patient_portal_setting
      return false unless setting

      cfg = setting.telemedicine_recording.is_a?(Hash) ? setting.telemedicine_recording : {}
      cfg.fetch('enabled', false)
    end

    def patient_consented?
      setting = @account&.patient_portal_setting
      cfg     = setting&.telemedicine_recording.is_a?(Hash) ? setting.telemedicine_recording : {}
      return true unless cfg.fetch('patient_consent_required', true)
      return false if @event.contact_id.blank?

      per_event_at = @event.custom_attributes&.dig('telemedicine_recording_consent_at')
      return true if per_event_at.present?

      patient = Patient.find_by(account_id: @account.id, contact_id: @event.contact_id)
      return false unless patient

      TelemedConsent
        .where(account_id: @account.id, patient_id: patient.id)
        .where(revoked_at: nil)
        .where.not(accepted_at: nil)
        .exists?
    end

    def existing_active_recording
      TelemedRecording
        .where(agenda_event_id: @event.id)
        .active_storage
        .where.not(status: %w[failed ready])
        .first
    end

    def resolve_participant_identities!
      response = room_service_client.list_participants(room: room_name(@event))
      participants = response.respond_to?(:participants) ? response.participants : []
      {
        doctor:  participants.find { |p| p.identity.to_s.start_with?('doctor-')  }&.identity,
        patient: participants.find { |p| p.identity.to_s.start_with?('patient-') }&.identity
      }
    end

    # 1 dos 2 ParticipantEgress (isolated, deletado após transcrição).
    def start_participant_audio_egress!(identity, role:)
      file_output = build_file_output(suffix: "#{role}-temp")
      opts        = audio_encoding_options

      egress_client.start_participant_egress(
        room_name(@event), identity, file_output, advanced: opts
      )
    rescue StandardError => e
      Rails.logger.error("[RecordingOrchestrator] ParticipantEgress role=#{role} #{e.class}: #{e.message}")
      nil
    end

    # RoomCompositeEgress audio_only — único arquivo que permanece.
    # `audio_mixing: DEFAULT_MIXING` mistura ambos os participantes em mono.
    def start_composite_audio_egress!
      file_output = build_file_output(suffix: 'composite')

      egress_client.start_room_composite_egress(
        room_name(@event),
        file_output,
        audio_only:  true,
        audio_mixing: LiveKit::Proto::AudioMixing::DEFAULT_MIXING,
        advanced:    audio_encoding_options
      )
    rescue StandardError => e
      Rails.logger.error("[RecordingOrchestrator] CompositeEgress #{e.class}: #{e.message}")
      nil
    end

    def build_file_output(suffix:)
      LiveKit::Proto::EncodedFileOutput.new(
        file_type: AUDIO_FILE_TYPE,
        filepath:  build_filepath(suffix),
        s3:        build_s3_upload
      )
    end

    def build_s3_upload
      LiveKit::Proto::S3Upload.new(
        access_key:       env_or_raise('TELEMED_STORAGE_ACCESS_KEY_ID', 'STORAGE_ACCESS_KEY_ID'),
        secret:           env_or_raise('TELEMED_STORAGE_SECRET_ACCESS_KEY', 'STORAGE_SECRET_ACCESS_KEY'),
        region:           ENV['TELEMED_STORAGE_REGION'].presence || ENV['STORAGE_REGION'].presence || 'auto',
        endpoint:         env_or_raise('TELEMED_STORAGE_ENDPOINT', 'STORAGE_ENDPOINT'),
        bucket:           env_or_raise('TELEMED_STORAGE_BUCKET', 'STORAGE_BUCKET_NAME'),
        force_path_style: true
      )
    end

    def audio_encoding_options
      LiveKit::Proto::EncodingOptions.new(
        audio_codec:     LiveKit::Proto::AudioCodec::OPUS,
        audio_bitrate:   AUDIO_BITRATE_BPS / 1_000, # proto espera kbps
        audio_frequency: 48_000
      )
    rescue NameError
      # Compatibilidade: se a versão do SDK não tem AudioCodec::OPUS, deixa
      # default (LiveKit Egress aplica opus pra OGG mesmo sem hint).
      nil
    end

    def build_filepath(suffix)
      # Convenção: accounts/{account_id}/telemed/{event_id}/{YYYY/MM/DD}/{suffix}-{egress_uuid}.ogg
      date = (@event.starts_at || Time.current).strftime('%Y/%m/%d')
      "accounts/#{@account.id}/telemed/#{@event.id}/#{date}/#{suffix}-{egress_uuid}.#{AUDIO_EXT}"
    end

    def room_name(event)
      "klivy-acc#{event.account_id}-event#{event.id}"
    end

    def egress_client
      @egress_client ||= (@livekit || default_egress_client)
    end

    def room_service_client
      @room_service_client ||= LiveKit::RoomServiceClient.new(
        egress_base_url,
        api_key:    @credentials.api_key,
        api_secret: @credentials.api_secret
      )
    end

    def default_egress_client
      LiveKit::EgressServiceClient.new(
        egress_base_url,
        api_key:    @credentials.api_key,
        api_secret: @credentials.api_secret
      )
    end

    def egress_base_url
      ENV['LIVEKIT_EGRESS_URL'].presence || @credentials.url
    end

    def env_or_raise(primary, fallback = nil)
      value = ENV[primary].presence
      value ||= ENV[fallback].presence if fallback
      value || raise("ENV var #{primary}#{fallback ? " (ou #{fallback})" : ''} obrigatória para Telemed Egress")
    end

    def skip(reason, recording: nil)
      Result.new(recording: recording, started: false, skipped_reason: reason)
    end
  end
end
