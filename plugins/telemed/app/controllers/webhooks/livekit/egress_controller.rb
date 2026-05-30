# Sprint L — Webhook do LiveKit Egress.
#
# LiveKit assina os webhooks com JWT no header `Authorization` (sem prefixo
# Bearer). Claim `sha256` contém o SHA-256 base64 do body cru — exigência pra
# garantir que o body não foi alterado em trânsito. Validação:
#   1) Decode JWT com api_secret das credenciais LiveKit
#   2) Issuer (`iss`) bate com api_key
#   3) SHA-256 do body raw bate com claim `sha256`
#
# Eventos relevantes:
#   - `egress_started`  → atualiza status pra 'recording'
#   - `egress_updated`  → atualiza file_results (intermediário; ignoramos em MVP)
#   - `egress_ended`    → arquivo finalizado no R2. Persistir storage_key,
#                         marcar status='uploaded', enfileirar TranscribeJob.
#                         (só enfileira quando AMBOS doctor+patient terminaram)
#
# Idempotência: lookup por egress_id; reaplica `update!` mesmo se chamado 2x.
require 'livekit'

class Webhooks::Livekit::EgressController < ActionController::API
  rescue_from StandardError, with: :handle_internal_error

  # POST /webhooks/livekit/egress
  def process_payload
    raw_body = request.raw_post

    unless verify_signature(raw_body, request.headers['Authorization'].to_s)
      Rails.logger.warn('[Webhooks::Livekit::EgressController] Assinatura inválida')
      return render json: { error: 'invalid_signature' }, status: :unauthorized
    end

    event = parse_event(raw_body)
    return render json: { error: 'invalid_payload' }, status: :unprocessable_entity if event.blank?

    handle_event(event)
    head :ok
  end

  private

  # LiveKit usa JWT HS256 com api_secret. Não há kid lookup multi-tenant aqui
  # porque self-hosted padrão usa creds globais — quando for necessário tenant
  # isolation, derivar account a partir do `room_name` claim e usar
  # CredentialsResolver.
  def verify_signature(body, auth_header)
    api_key    = ENV['LIVEKIT_API_KEY'].presence
    api_secret = ENV['LIVEKIT_API_SECRET'].presence
    return false if api_key.blank? || api_secret.blank? || auth_header.blank?

    # LiveKit envia o JWT puro no header Authorization (sem prefixo Bearer).
    # `.split.last` aceita ambos formatos sem brittleness: "Bearer JWT" → JWT,
    # "JWT" → JWT, "  JWT  " → JWT.
    token = auth_header.split.last.to_s.strip
    # AUDIT 2026-05-25 — adicionados `verify_iat` e `verify_expiration`.
    # LiveKit gera JWT com `iat`/`exp` curtos (~30s). Sem essas flags um
    # webhook capturado podia ser replayed indefinidamente (body+sha imutáveis
    # garantem só a integridade do payload, não a janela temporal). Idempotency
    # por (egress_id, event_type) ainda é débito P0 pendente.
    decoded, = JWT.decode(
      token,
      api_secret,
      true,
      algorithm: 'HS256',
      verify_iat: true,
      verify_expiration: true,
      # `leeway` cobre clock drift entre worker LiveKit e nosso app
      # (NTP em prod normalmente < 1s; 30s é o conservador de mercado).
      leeway: 30
    )
    return false if decoded['iss'] != api_key

    expected_sha = Base64.strict_encode64(Digest::SHA256.digest(body))
    # Comparison constant-time evita timing attacks vazando bytes da hash.
    ActiveSupport::SecurityUtils.secure_compare(decoded['sha256'].to_s, expected_sha)
  rescue JWT::ExpiredSignature => e
    Rails.logger.warn("[Webhooks::Livekit::EgressController] JWT expirado: #{e.message}")
    false
  rescue JWT::InvalidIatError => e
    Rails.logger.warn("[Webhooks::Livekit::EgressController] JWT iat inválido: #{e.message}")
    false
  rescue JWT::DecodeError => e
    Rails.logger.warn("[Webhooks::Livekit::EgressController] JWT decode falhou: #{e.message}")
    false
  end

  # Parse o body JSON (LiveKit pode mandar JSON ou Protobuf binário — usamos
  # JSON pela `Content-Type: application/webhook+json`). Em raras situações o
  # LiveKit envia protobuf — esse caminho lança aqui e o rescue_from converte
  # em 500; ajustar quando observado em prod.
  def parse_event(raw_body)
    JSON.parse(raw_body)
  rescue JSON::ParserError => e
    Rails.logger.warn("[Webhooks::Livekit::EgressController] JSON inválido: #{e.message}")
    nil
  end

  def handle_event(event)
    # Dispatch primeiro por tipo de evento — eventos não-egress (ex:
    # `track_published`) não têm `egressInfo` mas precisam ser roteados.
    # Antes o controller fazia early-return em `egress_id.blank?` e
    # silenciosamente ignorava todos os outros eventos do LiveKit.
    case event['event']
    when 'egress_started', 'egress_ended', 'egress_updated'
      handle_egress_event(event)
    when 'track_published'
      handle_track_published(event)
    else
      Rails.logger.info("[Webhooks::Livekit::EgressController] evento ignorado: #{event['event']}")
    end
  end

  def handle_egress_event(event)
    egress_info = event['egressInfo'] || event['egress_info'] || {}
    egress_id   = egress_info['egressId'] || egress_info['egress_id']
    return if egress_id.blank?

    # Race condition: o orchestrator faz `start_*_egress` e PERSISTE o
    # egress_id logo depois (window ~10-50ms). Webhook `egress_started`
    # também chega em ~50-200ms. Em casos extremos o webhook pode ganhar
    # a corrida. Retry curto (3x 150ms = 450ms) cobre o cenário.
    recording = find_recording_with_retry(egress_id)
    unless recording
      Rails.logger.info("[Webhooks::Livekit::EgressController] egress_id=#{egress_id} sem TelemedRecording após retries")
      return
    end

    case event['event']
    when 'egress_started'
      handle_started(recording)
    when 'egress_ended'
      handle_ended(recording, egress_info, egress_id)
    when 'egress_updated'
      Rails.logger.debug("[Webhooks::Livekit::EgressController] egress_updated egress=#{egress_id}")
    end
  end

  # `track_published`: persiste o sid do audio track no AgendaEvent. Fonte
  # canônica de track_sid pro TrackEgress — substitui o polling via
  # `RoomService.list_participants` (que devolve `tracks: []` na nossa
  # stack server 2.11 + gem 0.9). Quando o orchestrator roda `start!`,
  # ele lê estes sids de custom_attributes antes de tentar list_participants.
  #
  # Payload do LiveKit:
  #   { event: "track_published",
  #     room:        { name: "klivy-acc1-event77" },
  #     participant: { identity: "doctor-73-xxx" | "patient-12-xxx" },
  #     track:       { sid: "TR_xxx", type: "AUDIO" | "VIDEO", source: ... } }
  def handle_track_published(event)
    track = event['track'] || {}
    return unless track['type'].to_s.upcase == 'AUDIO'
    return if track['source'].to_s.upcase == 'SCREEN_SHARE_AUDIO'

    track_sid = track['sid']
    identity  = event.dig('participant', 'identity').to_s
    room_name = event.dig('room', 'name').to_s
    return if track_sid.blank? || identity.blank? || room_name.blank?

    role = identity.start_with?('doctor-')  ? 'doctor' :
           identity.start_with?('patient-') ? 'patient' : nil
    unless role
      Rails.logger.info(
        "[Webhooks::Livekit::EgressController] track_published ignorado " \
        "identity=#{identity} (não é doctor- nem patient-)"
      )
      return
    end

    event_record = find_event_by_room_name(room_name)
    return unless event_record

    persist_published_track(event_record, role: role, identity: identity, track_sid: track_sid)
    Rails.logger.info(
      "[Webhooks::Livekit::EgressController] track_published event=#{event_record.id} " \
      "role=#{role} identity=#{identity} track_sid=#{track_sid}"
    )
  end

  # Parser do room_name. Formato do orchestrator:
  #   "klivy-acc{account_id}-event{event_id}"
  # Carrega o evento ESCOPADO pelo account_id parseado — sem isso, um
  # payload com room_name forjado podia mexer em evento de outra clínica
  # (mesmo com signature válida, qualquer LiveKit válido seria aceito).
  # Multi-tenancy hard requirement.
  def find_event_by_room_name(room_name)
    match = room_name.match(/\Aklivy-acc(\d+)-event(\d+)\z/)
    return unless match

    account_id = match[1].to_i
    event_id   = match[2].to_i

    account = Account.find_by(id: account_id)
    return unless account

    account.agenda_events.find_by(id: event_id)
  end

  # Persiste em `custom_attributes['telemed_session']['published_tracks']`:
  #   { 'doctor'  => { 'identity' => '...', 'track_sid' => 'TR_...' },
  #     'patient' => { 'identity' => '...', 'track_sid' => 'TR_...' } }
  #
  # Idempotente: chamadas repetidas pro mesmo role apenas sobrescrevem
  # (republish após mute/unmute gera novo sid — queremos o mais recente).
  # Lock no evento serializa updates concorrentes (doctor + patient
  # publicando audio quase ao mesmo tempo).
  def persist_published_track(event_record, role:, identity:, track_sid:)
    event_record.with_lock do
      event_record.reload
      attrs   = event_record.custom_attributes || {}
      session = attrs['telemed_session'] || {}
      tracks  = session['published_tracks'] || {}
      tracks[role] = { 'identity' => identity, 'track_sid' => track_sid }
      session['published_tracks'] = tracks
      attrs['telemed_session']    = session
      event_record.update!(custom_attributes: attrs)
    end
  end

  def find_recording_with_retry(egress_id, attempts: 3, delay_seconds: 0.15)
    attempts.times do |i|
      rec = TelemedRecording.by_egress_id(egress_id).first
      return rec if rec

      sleep delay_seconds if i < attempts - 1
    end
    nil
  end

  def handle_started(recording)
    # Lock serializa 3 webhooks `egress_started` chegando em ms (doctor,
    # patient, composite) — sem isso 3 UPDATEs concorrentes (lost-update
    # inofensivo aqui, mas ainda desperdiça writes).
    transitioned = false
    recording.with_lock do
      return if recording.status != 'pending'

      recording.update!(status: 'recording')
      transitioned = true
    end

    # Broadcast fora do lock — não bloqueia a transação no Postgres com I/O
    # do Redis pub/sub. Só transmite se houve transição (evita spam).
    recording.broadcast_status_change! if transitioned
  end

  # Audio-only com até 3 egress jobs (doctor isolated + patient isolated +
  # composite). Quando todos os egress ESPERADOS terminarem, enfileira a
  # TranscribeRecordingJob. Esperado = aqueles que receberam egress_id na
  # criação (não-nulos). Se ParticipantEgress falhar, só esperamos pelo
  # composite — TranscribeJob detecta o cenário e roda em modo `single`.
  def handle_ended(recording, egress_info, egress_id)
    # Lock pessimista cobre o cenário em que 2-3 webhooks `egress_ended`
    # chegam quase simultâneos. Sem lock, cada webhook leia uma snapshot
    # parcial, computa `all_done` separadamente, e ambos podem enfileirar
    # TranscribeJob (custo Whisper duplicado). Lock + transitção de status
    # como guard garante enqueue único.
    enqueue_transcribe = false
    recording.with_lock do
      role = recording.role_for_egress_id(egress_id) # 'doctor'|'patient'|'composite'
      return unless role

      # 2026-05-22 — Antes só checávamos se `fileResults` estava vazio. Mas
      # quando o LiveKit Egress falha no upload S3, ele ainda manda o
      # `fileResults.filename` com o TEMPLATE não-substituído
      # (`composite-{egress_uuid}.ogg`). Sem o check de status, o webhook
      # tratava como sucesso, salvava o template literal no
      # `composite_audio_key`, e o `TranscribeRecordingJob` falhava com
      # `NoSuchKey` — mascarando upload-failure como transcrição-failure.
      # Agora respeita o campo `status` (EGRESS_FAILED / EGRESS_ABORTED).
      status      = egress_info['status'].to_s
      error_msg   = egress_info['error'].to_s
      if %w[EGRESS_FAILED EGRESS_ABORTED].include?(status)
        Rails.logger.error(
          "[Webhooks::Livekit::EgressController] egress=#{egress_id} role=#{role} " \
          "status=#{status} error=#{error_msg.inspect}"
        )
        fail_role!(recording, role)
        maybe_fail_recording!(
          recording.reload,
          reason: "Egress #{status} (#{role}): #{error_msg.presence || 'sem detalhe'}"
        )
        return
      end

      file_info   = first_file_info(egress_info)
      storage_key = file_info&.dig('location') || file_info&.dig('filename')

      if storage_key.blank?
        Rails.logger.error(
          "[Webhooks::Livekit::EgressController] egress=#{egress_id} role=#{role} " \
          'egress_ended sem fileResults (upload falhou ou stream sem dados)'
        )
        fail_role!(recording, role)
        maybe_fail_recording!(recording.reload)
        return
      end

      column = {
        'doctor'    => :doctor_audio_key,
        'patient'   => :patient_audio_key,
        'composite' => :composite_audio_key
      }[role]
      attrs = { column => storage_key }

      expected_keys = {
        'doctor'    => recording.doctor_egress_id.present?,
        'patient'   => recording.patient_egress_id.present?,
        'composite' => recording.composite_egress_id.present?
      }
      filled_keys = {
        'doctor'    => recording.doctor_audio_key.present?,
        'patient'   => recording.patient_audio_key.present?,
        'composite' => recording.composite_audio_key.present?
      }
      filled_keys[role] = true
      all_done = expected_keys.all? { |role_name, expected| !expected || filled_keys[role_name] }

      # Guard idempotência: só enfileira TranscribeJob na transição
      # `recording → uploaded`. Webhook replay encontrando status já
      # `uploaded`/`transcribing`/etc. não re-enqueue.
      transitioning_to_uploaded = all_done && recording.status == 'recording'
      if transitioning_to_uploaded
        attrs[:status]           = 'uploaded'
        attrs[:duration_seconds] = compute_duration(egress_info, recording)
        attrs[:total_size_bytes] = compute_total_size(egress_info, recording)
      end

      recording.update!(attrs)
      enqueue_transcribe = transitioning_to_uploaded
    end

    if enqueue_transcribe
      Rails.logger.info("[Webhooks::Livekit::EgressController] recording=#{recording.id} todos egress concluídos — enfileirando TranscribeJob")
      Telemed::TranscribeRecordingJob.perform_later(recording.id)
      # UI mostra "Aguardando processamento" → "Transcrevendo" quando o job
      # começa. Broadcast aqui sinaliza transição 'recording' → 'uploaded'.
      recording.broadcast_status_change!
    end
  end

  # Marca um role específico como falhado (zera o egress_id pra que
  # `expected_keys` não conte ele mais nas próximas iterações). NÃO marca
  # o recording todo como failed — pode haver outros roles ainda em curso.
  def fail_role!(recording, role)
    column = {
      'doctor'    => :doctor_egress_id,
      'patient'   => :patient_egress_id,
      'composite' => :composite_egress_id
    }[role]
    recording.update_column(column, nil) if column
  end

  # Se TODOS os egress IDs sumiram (todos falharam), aí sim marca o
  # recording inteiro como falhado. `reason` carrega a última mensagem
  # específica do Egress (status + error do payload do webhook) — sem
  # isso o `failure_reason` no DB ficava genérico ("Todos os egress
  # terminaram sem upload") e a UI mostrava só "(failed)", mascarando
  # erros de upload S3 como erros de transcrição.
  def maybe_fail_recording!(recording, reason: nil)
    return if recording.failed?
    return if recording.expected_egress_ids.any?

    recording.fail!(reason.presence || 'Todos os egress terminaram sem upload de áudio')
  end

  def first_file_info(egress_info)
    results = egress_info['fileResults'] || egress_info['file_results'] || []
    results.first
  end

  def compute_duration(egress_info, recording)
    new_duration = first_file_info(egress_info)&.dig('duration').to_i / 1_000_000_000 # ns → s
    [new_duration, recording.duration_seconds.to_i].max
  end

  def compute_total_size(egress_info, recording)
    new_size = first_file_info(egress_info)&.dig('size').to_i
    new_size + recording.total_size_bytes.to_i
  end

  def handle_internal_error(error)
    Rails.logger.error("[Webhooks::Livekit::EgressController] #{error.class}: #{error.message}")
    Rails.logger.error(error.backtrace&.first(5)&.join("\n"))
    # LiveKit retenta em 5xx por ~24h — devolvemos 500 pra manter idempotência.
    render json: { error: 'internal_error' }, status: :internal_server_error
  end
end
