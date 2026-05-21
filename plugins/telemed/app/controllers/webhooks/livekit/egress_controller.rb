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
    decoded, = JWT.decode(token, api_secret, true, algorithm: 'HS256')
    return false if decoded['iss'] != api_key

    expected_sha = Base64.strict_encode64(Digest::SHA256.digest(body))
    # Comparison constant-time evita timing attacks vazando bytes da hash.
    ActiveSupport::SecurityUtils.secure_compare(decoded['sha256'].to_s, expected_sha)
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
      # ignorado em MVP — só usaríamos pra UI mostrar progresso de upload
      Rails.logger.debug("[Webhooks::Livekit::EgressController] egress_updated egress=#{egress_id}")
    else
      Rails.logger.info("[Webhooks::Livekit::EgressController] evento ignorado: #{event['event']}")
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
  # recording inteiro como falhado.
  def maybe_fail_recording!(recording)
    return if recording.failed?
    return if recording.expected_egress_ids.any?

    recording.fail!('Todos os egress terminaram sem upload de áudio')
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
