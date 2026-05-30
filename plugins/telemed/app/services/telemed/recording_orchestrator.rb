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

    # Tentativas (10 × 0.8s = 8s total). LiveKit às vezes leva ~500ms pra
    # propagar a presença do participante pra room service API, e o `tracks`
    # array de `list_participants` em ParticipantInfo pode demorar mais que
    # isso pra ser populado (incompatibilidade observada server 2.11 + gem
    # 0.9). Sem retry suficiente, `start!` pulava cedo demais.
    PARTICIPANT_LOOKUP_ATTEMPTS    = 10
    PARTICIPANT_LOOKUP_INTERVAL_S  = 0.8

    # `force: true` é usado pelo endpoint manual de gravação (botão "Gravar"
    # do doutor na sala). Pula só o auto-enable do setting da conta — o
    # doutor está acionando manualmente, então o feature flag é irrelevante.
    # Consent do paciente PERMANECE obrigatório por LGPD/CFM mesmo no modo
    # manual (sem aceite, não grava).
    def start!(force: false)
      unless force || recording_enabled_for_account?
        Rails.logger.info("[RecordingOrchestrator] skip event=#{@event.id} reason=recording_disabled")
        return skip(:recording_disabled)
      end
      unless patient_consented?
        Rails.logger.info("[RecordingOrchestrator] skip event=#{@event.id} reason=consent_missing")
        return skip(:consent_missing)
      end

      identities = resolve_participant_identities_with_retry!
      unless both_participants_present?(identities)
        Rails.logger.warn(
          "[RecordingOrchestrator] skip event=#{@event.id} reason=participants_not_ready " \
          "doctor=#{identities[:doctor].inspect} patient=#{identities[:patient].inspect}"
        )
        return skip(:participants_not_ready)
      end

      # 2026-05-23 — Guard `both_have_audio_track?` REMOVIDO. Antes
      # exigíamos audio_track_sid de ambos pra diarização funcionar.
      # Mas: (1) o composite sempre captura áudio de quem TIVER mic
      # publicado; (2) o pipeline novo (`gpt-4o-transcribe-diarize`)
      # roda no composite e não precisa de tracks individuais; (3)
      # casos reais — paciente em ambiente com muito ruído pode mutar
      # o mic voluntariamente; bloquear gravação inteira nesse caso é
      # UX ruim. Agora: doctor sem mic → falha clara (não tem o que
      # gravar). Patient sem mic → grava só o que tiver (composite +
      # doctor track), e a transcrição final atribui o que detectar
      # como Doutor. TrackComposite per-participant é best-effort.
      unless identities.dig(:doctor, :audio_track_sid).present?
        Rails.logger.warn(
          "[RecordingOrchestrator] skip event=#{@event.id} reason=doctor_audio_missing " \
          "doctor=#{identities[:doctor].inspect}"
        )
        return skip(:doctor_audio_missing)
      end

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

      # Composite SEMPRE dispara — garante áudio da consulta inteira pro
      # Whisper. TrackEgress por participante é best-effort: roda se o
      # `RoomService.list_participants` devolveu o `audio_track_sid` (que
      # vai existir confiavelmente quando o webhook `track_published`
      # popular o campo no recording — TODO próximo commit). Sem track_sid,
      # cai pro modo `whisper-solo` no TranscribeJob (sem diarização, mas
      # consulta gravada e transcrita). É o trade-off correto: nunca
      # bloquear gravação por causa de uma feature que depende de polling
      # cuja API não é confiável.
      doctor_resp = start_track_audio_egress!(
        identities[:doctor][:audio_track_sid], role: 'doctor'
      )
      patient_resp = start_track_audio_egress!(
        identities[:patient][:audio_track_sid], role: 'patient'
      )
      composite_resp = start_composite_audio_egress!

      if any_started?(doctor_resp, patient_resp, composite_resp)
        recording.update!(
          doctor_egress_id:    doctor_resp&.egress_id,
          patient_egress_id:   patient_resp&.egress_id,
          composite_egress_id: composite_resp&.egress_id,
          status:              'recording',
          failure_reason:      nil
        )
      else
        # Nenhum Egress aceito — registro nasceu vazio (status=pending) e
        # a validação `at_least_one_egress_id_after_pending` IMPEDE
        # update!(status: 'failed') porque exige ≥1 egress_id em qualquer
        # estado fora de pending. Sem isso, o recording fica órfão em
        # pending pra sempre, e `existing_active_recording` faz o próximo
        # joined! pular start! (consulta inteira sem gravação, exatamente
        # o que aconteceu no incidente de 2026-05-20). update_columns
        # pula validação — mesma estratégia de `fail!` no model.
        recording.update_columns(
          status:         'failed',
          failure_reason: 'Falha ao iniciar Egress',
          updated_at:     Time.current
        )
      end

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

    # Retorna identity + sid do audio track de cada role. Sid do track é
    # essencial pro TrackEgress (que substitui o ParticipantEgress — ver
    # comentário em `start_track_audio_egress!`).
    def resolve_participant_identities!
      response = room_service_client.list_participants(room: room_name(@event))
      payload  = unwrap_twirp(response)
      participants = payload.respond_to?(:participants) ? payload.participants : []

      # Instrumentação 2026-05-22 — print do payload bruto pra investigar
      # por que `tracks` chega vazio mesmo com microfones publicando.
      # Loga state, kind, num tracks e identidade de cada um. Remover quando
      # diagnóstico estiver claro.
      Rails.logger.info(
        "[RecordingOrchestrator] list_participants room=#{room_name(@event)} " \
        "count=#{participants.size} payload=#{participants.map do |p|
          {
            identity:     p.identity,
            state:        p.respond_to?(:state) ? p.state : nil,
            kind:         p.respond_to?(:kind) ? p.kind : nil,
            is_publisher: p.respond_to?(:is_publisher) ? p.is_publisher : nil,
            tracks_count: (p.tracks || []).size,
            tracks: (p.tracks || []).map { |t| { sid: t.sid, type: t.type, source: t.source, muted: t.muted } }
          }
        end.inspect}"
      )

      # Source canônica de track_sid: webhook `track_published` (persiste
      # em `event.custom_attributes['telemed_session']['published_tracks']`).
      # Polling de list_participants é fallback porque na nossa stack
      # (server 2.11 + gem 0.9) o campo `tracks` chega vazio mesmo com
      # audio publicado há minutos. Webhook é confiável por ser server-push.
      published_tracks = webhook_published_tracks

      result = { doctor: nil, patient: nil }
      participants.each do |p|
        role = if p.identity.to_s.start_with?('doctor-')
                 :doctor
               elsif p.identity.to_s.start_with?('patient-')
                 :patient
               end
        next unless role

        webhook_sid = published_tracks.dig(role.to_s, 'track_sid')
        # 2026-05-22 — Comparação via `.to_s == 'AUDIO'` (não `== ::LiveKit::
        # Proto::TrackType::AUDIO`). O protobuf-ruby desserializa enum como
        # Symbol (`:AUDIO`), mas a constante `::LiveKit::Proto::TrackType::
        # AUDIO` é o Integer underlying (`0`). `:AUDIO == 0` é false →
        # `audio_track` sempre era nil → TrackEgress nunca disparava
        # silenciosamente → toda gravação caía em composite-only com
        # speaker "Participante". Mesma armadilha pro `source` (`:MICROPHONE`
        # vs `::TrackSource::SCREEN_SHARE_AUDIO` que é `4`).
        polled_sid = (p.tracks || []).find do |t|
          next false unless t.respond_to?(:type)
          t.type.to_s == 'AUDIO' && t.source.to_s != 'SCREEN_SHARE_AUDIO'
        end&.sid

        result[role] = {
          identity:        p.identity,
          # Webhook ganha — quando ambos têm valor, são o mesmo sid;
          # quando só um, webhook é o que sobrevive ao bug de polling.
          audio_track_sid: webhook_sid.presence || polled_sid
        }
      end
      result
    end

    def webhook_published_tracks
      @event.reload.custom_attributes&.dig('telemed_session', 'published_tracks') || {}
    end

    # livekit-server-sdk 0.9.x devolve `Twirp::ClientResp` em todas as RPCs
    # (antes a chamada já retornava o proto direto). A `.data` carrega o
    # proto de fato (`ListParticipantsResponse`, `EgressInfo`, etc.) e
    # `.error` traz erro Twirp se houver. Se o gem voltar a devolver o
    # proto direto, esse helper passa o objeto adiante sem mexer.
    #
    # Bug 2026-05-22 — sem isso, `respond_to?(:participants)` era `false`
    # no Twirp::ClientResp e o fallback `[]` mascarava TODA gravação:
    # doctor=nil/patient=nil sempre, mesmo com a sala cheia.
    def unwrap_twirp(response)
      return response unless defined?(Twirp::ClientResp) && response.is_a?(Twirp::ClientResp)
      if response.error
        raise "Twirp error: code=#{response.error.code} msg=#{response.error.msg}"
      end
      response.data
    end

    # joined! dispara start! no exato momento em que o segundo participante
    # entra. LiveKit propaga a presença pra room service de forma assíncrona
    # (latência observada: 200-800ms). Sem retry curto, start! pulava com
    # `participants_not_ready` e a consulta ficava sem gravação.
    #
    # 2026-05-22 — Antes esse retry também era usado pra esperar o audio
    # track ser publicado (campo `audio_track_sid` no payload). Aconteceu
    # que `RoomService.list_participants` do livekit-server-sdk 0.9 NÃO
    # retorna tracks populados nessa API — track info vem via webhook
    # `track_published`, não polling. Resultado: `audio_track_sid` ficava
    # eternamente nil e o guard impedia toda gravação ("Aguarde o paciente
    # entrar de fato na sala" mesmo com 2 vídeos visíveis na tela). Agora
    # o critério de "pronto pra gravar" é só identidade dos 2 participantes
    # — track_sid vira best-effort no start! e cai pra composite-only se
    # vazio. Próximo commit: persistir track_sid via webhook handler.
    def resolve_participant_identities_with_retry!
      attempts = 0
      identities = { doctor: nil, patient: nil }
      while attempts < PARTICIPANT_LOOKUP_ATTEMPTS
        attempts += 1
        identities = resolve_participant_identities!
        ready = both_participants_present?(identities)
        break if ready
        if attempts < PARTICIPANT_LOOKUP_ATTEMPTS
          Rails.logger.info(
            "[RecordingOrchestrator] participants_not_ready event=#{@event.id} " \
            "attempt=#{attempts}/#{PARTICIPANT_LOOKUP_ATTEMPTS} " \
            "doctor=#{identities[:doctor].inspect} patient=#{identities[:patient].inspect} — retrying"
          )
          sleep(PARTICIPANT_LOOKUP_INTERVAL_S)
        end
      end
      identities
    end

    def both_participants_present?(identities)
      d = identities[:doctor]
      p = identities[:patient]
      d.is_a?(Hash) && p.is_a?(Hash) &&
        d[:identity].present? && p[:identity].present?
    end

    # Ambos publicaram audio track? Necessário pra TrackCompositeEgress
    # por participante funcionar (diarização). Se um lado não publicou,
    # o orchestrator falha cedo com `skip(:audio_track_missing)` em vez
    # de criar recording sem diarização.
    def both_have_audio_track?(identities)
      d = identities[:doctor]
      p = identities[:patient]
      d.is_a?(Hash) && p.is_a?(Hash) &&
        d[:audio_track_sid].present? && p[:audio_track_sid].present?
    end

    # 1 dos 2 TrackCompositeEgress isolated (audio-only, re-encodado pra
    # OGG opus) — deletado após transcrição. Cada arquivo carrega APENAS
    # o áudio do speaker correspondente → TranscribeJob roda Whisper x2
    # com speaker garantido (doctor.ogg = Doutor, patient.ogg = Paciente).
    #
    # 2026-05-22 v3 — Trocado `start_track_egress` por
    # `start_track_composite_egress`. TrackEgress salva RAW RTP packets
    # num container OGG (sem re-encode, sem normalização) — Whisper
    # rejeita esse formato com transcrição corrompida ("Se eu tivesse um
    # caso..." em vez de "celular"). TrackComposite re-encoda pra OGG
    # opus limpo via EncodingOptions (mesmas opts do composite que
    # transcreve direito).
    #
    # Histórico (mantido pra contexto):
    # - v1: `start_participant_egress` — falhou com "format audio/ogg
    #   incompatible with codec" (sem flag audio_only na API).
    # - v2: `start_track_egress` + DirectFileOutput — funcionou pra
    #   gravar mas Whisper não digere RAW RTP.
    # - v3 (atual): `start_track_composite_egress` — re-encode + audio
    #   limpo.
    def start_track_audio_egress!(track_sid, role:)
      return nil if track_sid.blank?

      file_output = build_file_output(suffix: "#{role}-temp")
      response = egress_client.start_track_composite_egress(
        room_name(@event),
        file_output,
        audio_track_id: track_sid,
        advanced:       audio_encoding_options
      )
      unwrap_twirp(response)
    rescue StandardError => e
      Rails.logger.error("[RecordingOrchestrator] TrackCompositeEgress role=#{role} #{e.class}: #{e.message}")
      nil
    end

    # RoomCompositeEgress audio_only — único arquivo que permanece.
    # `audio_mixing: DEFAULT_MIXING` mistura ambos os participantes em mono.
    # Ver comentário em `start_participant_audio_egress!` sobre o uso de array.
    def start_composite_audio_egress!
      file_output = build_file_output(suffix: 'composite')

      response = egress_client.start_room_composite_egress(
        room_name(@event),
        [file_output],
        audio_only:  true,
        audio_mixing: LiveKit::Proto::AudioMixing::DEFAULT_MIXING,
        advanced:    audio_encoding_options
      )
      unwrap_twirp(response)
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

    # TrackEgress aceita SÓ `DirectFileOutput` (raw bytes do track RTP, sem
    # re-encode). LiveKit detecta a extensão pelo `filepath` — `.ogg` pro
    # opus stream que o LiveKit JS publica nativo (`opus/red`).
    def build_direct_file_output(suffix:)
      LiveKit::Proto::DirectFileOutput.new(
        filepath: build_filepath(suffix),
        s3:       build_s3_upload
      )
    end

    def build_s3_upload
      LiveKit::Proto::S3Upload.new(
        access_key:       env_or_raise('TELEMED_STORAGE_ACCESS_KEY_ID', 'STORAGE_ACCESS_KEY_ID'),
        secret:           env_or_raise('TELEMED_STORAGE_SECRET_ACCESS_KEY', 'STORAGE_SECRET_ACCESS_KEY'),
        region:           ENV['TELEMED_STORAGE_REGION'].presence || ENV['STORAGE_REGION'].presence || 'auto',
        # 2026-05-22 — Em dev, LiveKit Egress roda no container Docker e
        # `localhost` dentro do container é o próprio container (não o
        # host onde o MinIO está). Usa INTERNAL_ENDPOINT
        # (`http://host.docker.internal:9000`) quando definido — só pro
        # caminho Egress→Storage. Em prod (R2/S3 real), essa env fica
        # vazia e cai no `TELEMED_STORAGE_ENDPOINT` normal. O Rails
        # (RecordingStorage) continua usando `TELEMED_STORAGE_ENDPOINT`
        # porque roda no host, não no container.
        endpoint:         ENV['TELEMED_STORAGE_INTERNAL_ENDPOINT'].presence ||
                          env_or_raise('TELEMED_STORAGE_ENDPOINT', 'STORAGE_ENDPOINT'),
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
      # Convenção: accounts/{account_id}/telemed/{event_id}/{YYYY/MM/DD}/{suffix}-{nonce}.ogg
      #
      # 2026-05-22 — Antes usávamos o placeholder `{egress_uuid}` esperando
      # que o LiveKit Egress fizesse a substituição. O Egress 2.11 NÃO faz:
      # salva o arquivo com o nome LITERAL `composite-{egress_uuid}.ogg`,
      # com chaves e tudo. Resultado: `URI(key)` no RecordingStorage falhava
      # com URI::InvalidURIError (`{`/`}` ilegais), o arquivo ficava órfão,
      # transcrição nunca rodava. Geramos o UUID no Ruby — funciona em
      # qualquer versão do Egress e o path no DB combina exato com o
      # objeto persistido no storage.
      date  = (@event.starts_at || Time.current).strftime('%Y/%m/%d')
      nonce = SecureRandom.hex(8)
      "accounts/#{@account.id}/telemed/#{@event.id}/#{date}/#{suffix}-#{nonce}.#{AUDIO_EXT}"
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
