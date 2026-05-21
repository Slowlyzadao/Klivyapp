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
    [[params[:per_page].to_i, PER_PAGE_DEFAULT].max, PER_PAGE_MAX].min
  end

  def offset
    (page - 1) * per_page
  end

  def latest_recording_for(event)
    event.telemed_recordings.order(created_at: :desc).first
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
    {
      id:          event.id,
      title:       event.title,
      starts_at:   event.starts_at,
      ends_at:     event.ends_at,
      status:      event.status,
      patient: {
        contact_id: event.contact_id,
        patient_id: event.contact&.patient&.id,
        name:       event.contact&.name
      },
      professional: {
        user_id: event.user_id,
        name:    event.user&.name
      },
      duration_minutes: ((event.ends_at - event.starts_at) / 60).to_i,
      recording: recording && {
        id:                recording.id,
        status:            recording.status,
        duration_seconds:  recording.duration_seconds,
        started_at:        recording.created_at,
        has_transcript:    recording.transcript_text.present?
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

    summary.merge(
      room_code: Telemed::RoomCode.from_event(event, patient: event.contact),
      recording: recording && recording.to_summary_hash.merge(
        transcript_segments: recording.transcript_segments,
        transcript_text:     recording.transcript_text
      ),
      evolution: evolution && {
        id:               evolution.id,
        status:           evolution.status,
        provider:         evolution.provider,
        soap_structure:   evolution.soap_structure,
        raw_markdown:     evolution.raw_markdown,
        attention_points: evolution.attention_points,
        reviewed_by:      evolution.reviewed_by&.name,
        reviewed_at:      evolution.reviewed_at,
        clinical_note_id: evolution.clinical_note_id
      }
    )
  end
end
