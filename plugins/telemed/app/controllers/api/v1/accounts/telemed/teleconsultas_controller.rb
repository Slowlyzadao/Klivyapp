# Listagem e detalhe de teleconsultas (visão clínica).
#
# Indexa AgendaEvents que têm telemedicina habilitada (custom_attributes.
# telemedicine_provider presente ou recordings associados). Filtros por
# tab (upcoming/in_progress/finished/no_show), profissional, range.
#
# Pundit: reaproveita `AgendaEventPolicy` — quem vê evento na agenda vê na
# teleconsulta. Filtragem por `scope=own` aplica automaticamente.
class Api::V1::Accounts::Telemed::TeleconsultasController < Api::V1::Accounts::BaseController
  before_action :load_agenda_event, only: [:show, :recording_url, :retranscribe, :reevolve]

  TABS = {
    'upcoming'    => %w[scheduled confirmed],
    'in_progress' => %w[arrived in_progress],
    'finished'    => %w[completed],
    'no_show'     => %w[no_show]
  }.freeze
  PER_PAGE_DEFAULT = 20
  PER_PAGE_MAX     = 100

  # GET /api/v1/accounts/:account_id/telemed/teleconsultas
  def index
    authorize AgendaEvent, :index?

    scope = policy_scope(Current.account.agenda_events.kept)
            .includes(:user, :agenda_service, contact: :patient, telemed_recordings: :proposed_evolutions)

    scope = scope_by_tab(scope, params[:tab])
    scope = scope_by_filters(scope, params)
    scope = scope.where('agenda_events.starts_at >= ?', Time.current - 60.days) if params[:date_from].blank?

    @events = scope.order(starts_at: :desc).limit(per_page).offset(offset)

    render json: {
      data: @events.map { |e| serialize_summary(e) },
      meta: {
        tab: params[:tab].presence || 'upcoming',
        page: page,
        per_page: per_page,
        has_more: @events.size == per_page
      }
    }
  end

  # GET /api/v1/accounts/:account_id/telemed/teleconsultas/counts
  # Retorna contagens por aba em uma única query agregada. Usa o mesmo
  # filtro de starts_at >= now - 60d das listas para manter consistência.
  def counts
    authorize AgendaEvent, :index?

    scope = policy_scope(Current.account.agenda_events.kept)
            .where('agenda_events.starts_at >= ?', Time.current - 60.days)

    grouped = scope.group(:status).count
    by_tab = TABS.transform_values { |statuses| statuses.sum { |s| grouped[s].to_i } }

    render json: { data: by_tab }
  end

  # GET /api/v1/accounts/:account_id/telemed/teleconsultas/:id
  def show
    authorize @event, :show?
    render json: { data: serialize_detail(@event) }
  end

  # GET /api/v1/accounts/:account_id/telemed/teleconsultas/:id/recording_url
  # ?kind=doctor_video|patient_video|composite
  def recording_url
    authorize @event, :show?
    recording = latest_recording_for(@event)
    return render json: { error: 'Sem gravação disponível' }, status: :not_found unless recording

    # AUDIT 2026-05-25 — guard contra race entre `latest_recording_for` e a
    # leitura da key. EnforceRecordingQuotaJob pode marcar `archived_at` e
    # deletar o objeto no R2 entre a query (40ms atrás) e este ponto.
    # Resultado: signed URL emitida pra objeto inexistente (404 no player) ou,
    # pior, ainda existente in-flight de delete — exibindo áudio recém-arquivado
    # que deveria estar inacessível.
    if recording.archived?
      return render json: { error: 'Gravação arquivada', code: 'recording_archived' },
                    status: :not_found
    end

    key = pick_storage_key(recording, params[:kind])
    return render json: { error: 'Tipo de arquivo inválido ou não disponível' }, status: :unprocessable_entity if key.blank?

    url = Telemed::RecordingStorage.signed_url(key)
    render json: { data: { url: url, expires_in: 300, kind: params[:kind] } }
  rescue RuntimeError => e
    Rails.logger.error("[Teleconsultas#recording_url] #{e.class}: #{e.message}")
    render json: { error: 'Storage indisponível' }, status: :service_unavailable
  end

  # POST /api/v1/accounts/:account_id/telemed/teleconsultas/:id/retranscribe
  # Admin-only: refaz transcrição (debug ou falha pontual).
  def retranscribe
    authorize @event, :update?
    recording = latest_recording_for(@event)
    return render json: { error: 'Sem gravação para retranscrever' }, status: :not_found unless recording

    recording.update!(status: 'uploaded', retry_count: 0, failure_reason: nil)
    Telemed::TranscribeRecordingJob.perform_later(recording.id)
    head :accepted
  end

  # POST /api/v1/accounts/:account_id/telemed/teleconsultas/:id/reevolve
  # Admin-only: regera evolução (ex. trocar provider).
  def reevolve
    authorize @event, :update?
    recording = latest_recording_for(@event)
    return render json: { error: 'Sem transcrição para gerar evolução' }, status: :not_found unless recording&.transcript_text.present?

    recording.update!(status: 'transcribed', retry_count: 0)
    Telemed::GenerateEvolutionJob.perform_later(recording.id)
    head :accepted
  end

  private

  def load_agenda_event
    @event = Current.account.agenda_events.find(params[:id])
  end

  def scope_by_tab(scope, tab)
    statuses = TABS[tab.to_s] || TABS['upcoming']
    scope.where(status: statuses)
  end

  def scope_by_filters(scope, params)
    scope = scope.where(user_id: params[:professional_id]) if params[:professional_id].present?
    if params[:date_from].present? && params[:date_to].present?
      scope = scope.where(starts_at: params[:date_from]..params[:date_to])
    end
    scope
  end

  def page
    [params[:page].to_i, 1].max
  end

  def per_page
    # AUDIT 2026-05-25 — antes `[[to_i, DEFAULT].max, MAX].min` clampava
    # qualquer valor < DEFAULT pra DEFAULT (per_page=5 virava 20). Agora
    # respeita o pedido se positivo, cai pra DEFAULT em 0/negativo/nil,
    # e clampa no MAX.
    requested = params[:per_page].to_i
    return PER_PAGE_DEFAULT unless requested.positive?

    [requested, PER_PAGE_MAX].min
  end

  def offset
    (page - 1) * per_page
  end

  # Cache local por event_id pra evitar N+1 em `index`:
  # `serialize_summary` é chamado pra cada event no loop, e dentro dele este
  # método + `latest_proposed_evolution` eram chamados sem cache. 20 events
  # × 3 acessos = 60 queries extras antes do cache; agora é constante.
  # Quando a associação está preloaded (via `.includes` no index), usa
  # `max_by` em memória; no show endpoint (sem includes), cai pro DB com
  # `order().first`. Mesmo escopo da request — `@latest_recording` reseta
  # entre requests (Rails recria o controller).
  def latest_recording_for(event)
    @latest_recording ||= {}
    # AUDIT 2026-05-25 — `||=` em hash retorna nil quando a key existe com
    # valor nil, repetindo a query a cada chamada. `fetch ... { }` armazena
    # o nil também, satisfazendo o objetivo de memoização real.
    @latest_recording.fetch(event.id) do
      @latest_recording[event.id] =
        if event.association(:telemed_recordings).loaded?
          event.telemed_recordings.max_by(&:created_at)
        else
          event.telemed_recordings.order(created_at: :desc).first
        end
    end
  end

  def pick_storage_key(recording, kind)
    # MVP é audio-only. doctor_audio_key/patient_audio_key são temporários
    # e deletados após transcrição — só o composite_audio_key persiste pro player.
    case kind.to_s
    when 'audio', 'composite_audio', '' then recording.composite_audio_key
    when 'doctor_audio'                 then recording.doctor_audio_key
    when 'patient_audio'                then recording.patient_audio_key
    end
  end

  def serialize_summary(event)
    recording = latest_recording_for(event)
    evolution = recording&.latest_proposed_evolution
    patient   = event.contact&.patient
    # Patient é fonte da verdade do nome (cadastro clínico). Contact (Chatwoot)
    # pode estar dessincronizado — ex.: contato criado via WhatsApp com nome do
    # número e depois vinculado a um Patient com nome real. Audit teleconsulta
    # 2026-05-25.
    patient_name = patient&.name.presence || event.contact&.name
    service      = event.agenda_service
    {
      id:          event.id,
      title:       event.title,
      starts_at:   event.starts_at,
      ends_at:     event.ends_at,
      status:      event.status,
      patient: {
        contact_id: event.contact_id,
        patient_id: patient&.id,
        name:       patient_name,
        # Avatar do contato (foto enviada ou gravatar). Card usa o componente
        # padrão Avatar — com src cai pra iniciais quando nil.
        avatar_url: event.contact&.avatar_url.presence
      },
      professional: {
        user_id: event.user_id,
        name:    event.user&.name
      },
      # 2026-05-25 — `service` (treatment selecionado) e `reason` (descrição)
      # são o motivo verdadeiro da consulta. `title` NÃO entra aqui porque o
      # modal auto-preenche com nome do paciente p/ label do calendário; usar
      # como motivo gerava "Bruna Lopes Oliveira" no campo "Motivo" do card.
      service: service && {
        id:    service.id,
        name:  service.name,
        color: service.respond_to?(:color) ? service.color : nil
      },
      reason: event.description.to_s.strip.presence,
      duration_minutes: ((event.ends_at - event.starts_at) / 60).to_i,
      recording: recording && {
        id:                recording.id,
        status:            recording.status,
        duration_seconds:  recording.duration_seconds,
        started_at:        recording.created_at,
        # has_transcript via STATUS, não acessando recording.transcript_text
        # diretamente. O atributo é `encrypts :transcript_text`, e em
        # ambientes sem `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY` configurado
        # (dev sem ENV set) qualquer leitura do atributo levanta
        # ActiveRecord::Encryption::Errors::Configuration → 500 no /finished.
        # Status >= 'transcribed' implica transcript persistido, é o mesmo
        # sinal sem precisar de decryption.
        has_transcript:    %w[transcribed evolving ready].include?(recording.status)
      },
      evolution: evolution && {
        id:     evolution.id,
        status: evolution.status
      }
    }
  end

  def serialize_detail(event)
    recording = latest_recording_for(event)
    evolution = recording&.latest_proposed_evolution
    summary   = serialize_summary(event)

    # AUDIT 2026-05-25 — antes lia `recording.transcript_text` e
    # `transcript_segments` sem checar status. `transcript_text` é
    # `encrypts` (LGPD) — em ambientes sem ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY
    # qualquer leitura levanta Encryption::Errors::Configuration → 500 na
    # tela de detalhe. `serialize_summary` já tinha o guard via `has_transcript`;
    # aqui replicamos a mesma defesa: só lê se o status indica transcript
    # persistido. `transcript_segments` é jsonb plaintext mas seguimos a mesma
    # gate por simetria/UX (não faz sentido entregar segments sem texto).
    transcript_ready = %w[transcribed evolving ready].include?(recording&.status)

    summary.merge(
      room_code: Telemed::RoomCode.from_event(event, patient: event.contact),
      recording: recording && recording.to_summary_hash.merge(
        transcript_segments: transcript_ready ? recording.transcript_segments : nil,
        transcript_text:     transcript_ready ? recording.transcript_text     : nil
      ),
      evolution: evolution && {
        id:               evolution.id,
        status:           evolution.status,
        provider:         evolution.provider,
        soap_structure:   evolution.soap_structure,
        raw_markdown:     evolution.raw_markdown,
        # 2026-05-22 — Resumo Executivo (Markdown). UI renderiza via
        # markdown-it. Vazio em evoluções antigas (pré-fix) até reprocessar.
        summary:          evolution.summary.to_s,
        attention_points: evolution.attention_points,
        # 2026-05-26 — Registro de Procedimento (14 campos editáveis).
        # Vazio {} em evoluções antigas (pré-audit) até reprocessar.
        procedure_fields: evolution.procedure_fields || {},
        reviewed_by:      evolution.reviewed_by&.name,
        reviewed_at:      evolution.reviewed_at,
        clinical_note_id: evolution.clinical_note_id
      }
    )
  end
end
