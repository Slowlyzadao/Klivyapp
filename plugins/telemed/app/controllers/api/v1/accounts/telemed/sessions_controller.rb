# Token JWT + reportagem de joined/left para o lado DENTISTA da sala.
#
# Antes: actions `telemedicine_token`/`telemedicine_event` viviam em
# `agenda_events_controller`. Extraídas pra cá quando o módulo virou plugin
# próprio.
#
# Autorização: Pundit `telemedicine_join?` no AgendaEvent — só o dono do
# horário pode entrar/reportar.
class Api::V1::Accounts::Telemed::SessionsController < Api::V1::Accounts::BaseController
  before_action :load_event

  # POST /api/v1/accounts/:account_id/telemed/sessions?event_id=:id
  # Gera token JWT pro profissional entrar na sala LiveKit.
  #
  # Identity do token vem como "doctor-#{user.id}". O paciente entra como
  # "patient-#{patient.id}" — identities distintas garantem que o LiveKit
  # trate como participants separados (necessário pro PIP/active-speaker).
  def create
    authorize @event, :telemedicine_join?

    telemed = Telemed::Session.new(event: @event, account: Current.account).call

    # 2026-05-19 — Doutor entra a qualquer hora (Google Meet pattern).
    # Só recusamos bloqueios permanentes (cancelado, status final, sem
    # horário, telemed desligado). too_early / window_closed deixam passar.
    if telemed.permanently_blocked?
      reason_code = telemed.enabled? ? telemed.reason : 'telemedicine_not_enabled'
      return render json: { error: 'Esta consulta não está mais disponível para teleconsulta.', code: reason_code },
                    status: :unprocessable_entity
    end

    session = Telemed::SessionIssuer.new(
      event:       @event,
      participant: Current.user,
      role:        'doctor',
      admitted:    true  # doutor entra com canPublish=true direto
    ).call

    # 2026-05-21 — Devolve `admissions` (identities já admitidas) pra que a
    # UI do dentista reidrate o estado: se ele recarrega a página, pacientes
    # já aceitos não voltam pro card "Aceitar".
    #
    # 2026-05-22 — Filtra pela janela do evento via AdmissionWindow. Sem
    # isso, admissão de sessão antiga (mesmo agenda_event_id, mas em hora
    # diferente do dia) fazia o front pular o card de admit pra sempre.
    # Mesmo helper que o patient_portal usa em patient_already_admitted? —
    # garante que admin e paciente decidem com critério idêntico.
    persisted_admissions = Telemed::AdmissionWindow.new(event: @event).valid_admissions

    # 2026-05-22 — Estado da gravação manual. Doutor controla via botão na
    # toolbar; se ele recarregar a página no meio da consulta, recovery vê
    # `recording.active: true` e mantém o ícone vermelho aceso.
    active_rec = @event.telemed_recordings
                       .where(status: %w[pending recording])
                       .order(created_at: :desc)
                       .first
    recording_state = {
      active:     active_rec.present? && active_rec.status == 'recording',
      # `started_at` na payload mantém o nome semântico esperado pelo front
      # (badge "REC IA" + recovery após F5). No model só temos `created_at`
      # — coincide com o momento real do start porque o registro nasce
      # nesse instante via TelemedRecording.create!.
      started_at: active_rec&.created_at&.iso8601,
      consented:  @event.custom_attributes&.[]('telemedicine_recording_consent_at').present?
    }

    payload = session.to_h.merge(
      outside_window:    telemed.outside_window?,
      starts_in_seconds: telemed.starts_in_seconds,
      ends_in_seconds:   telemed.ends_in_seconds,
      window_reason:     telemed.reason,
      admissions:        persisted_admissions,
      recording:         recording_state
    )

    render json: {
      data: payload,
      meta: {
        outside_window:    telemed.outside_window?,
        starts_in_seconds: telemed.starts_in_seconds,
        ends_in_seconds:   telemed.ends_in_seconds,
        reason:            telemed.reason
      }
    }
  rescue Pundit::NotAuthorizedError
    raise
  rescue StandardError => e
    Rails.logger.error("[Telemed::Sessions#create] #{e.class}: #{e.message}")
    render json: { error: 'Não foi possível gerar o acesso à sala.', code: 'telemedicine_issue_failed' },
           status: :internal_server_error
  end

  # POST /api/v1/accounts/:account_id/telemed/sessions/admit_patient?event_id=:id
  # Dentista aceitou um paciente que estava na sala de espera.
  # Chama LiveKit UpdateParticipant pra liberar canPublish=true + persiste
  # registro em custom_attributes['telemed_session']['admissions'].
  #
  # 2026-05-21 — Antes a admissão era 100% client-side (data channel). Agora
  # é server-side: LiveKit reescreve a permission do token na hora.
  def admit_patient
    authorize @event, :telemedicine_join?

    identity = params[:identity].to_s.strip
    if identity.blank? || !identity.start_with?('patient-')
      return render json: { error: 'identity inválida', code: 'invalid_identity' },
                    status: :unprocessable_entity
    end

    result = Telemed::ParticipantAdmitter.new(event: @event, identity: identity).call

    if result.ok?
      render json: {
        data: {
          identity:    identity,
          admitted_at: result.admitted_at.iso8601
        }
      }
    else
      render json: { error: 'Não foi possível admitir o paciente.', code: result.error },
             status: :unprocessable_entity
    end
  rescue Pundit::NotAuthorizedError
    raise
  rescue StandardError => e
    Rails.logger.error("[Telemed::Sessions#admit_patient] #{e.class}: #{e.message}")
    render json: { error: 'Falha ao admitir paciente.', code: 'admit_failed' },
           status: :internal_server_error
  end

  # POST /api/v1/accounts/:account_id/telemed/sessions/event?event_id=:id&kind=joined|left
  # Frontend (admin) reporta join/leave da sala. Aciona SessionEventHandler.
  def event
    authorize @event, :telemedicine_join?

    kind = params[:kind].to_s
    unless %w[joined left].include?(kind)
      return render json: { error: 'Tipo de evento inválido.' }, status: :unprocessable_entity
    end

    handler = Telemed::SessionEventHandler.new(event: @event, role: 'doctor')
    result = kind == 'joined' ? handler.joined! : handler.left!

    render json: {
      data: {
        event_id: @event.id,
        status:   @event.reload.status,
        session:  result.session.to_h,
        scheduled_jobs: result.scheduled_jobs
      }
    }
  rescue Pundit::NotAuthorizedError
    raise
  rescue StandardError => e
    Rails.logger.error("[Telemed::Sessions#event] #{e.class}: #{e.message}")
    render json: { error: 'Não foi possível registrar o evento da sessão.', code: 'telemedicine_event_failed' },
           status: :internal_server_error
  end

  # POST /api/v1/accounts/:account_id/telemed/sessions/start_recording?event_id=:id
  # Doutor clicou no botão "Gravar" na toolbar da sala. Chama
  # RecordingOrchestrator com `force: true` (pula o auto-enable do setting
  # da conta — decisão manual do doutor). Consent do paciente PERMANECE
  # obrigatório (LGPD/CFM).
  #
  # 2026-05-22 — Antes a gravação era 100% automática no `joined!`, mas
  # com falhas silenciosas frequentes (`participants_not_ready` quando o
  # SFU demorava pra propagar presença, e o doutor saía sem gravar). Agora
  # o doutor tem controle direto: vê o botão e o status em tempo real.
  def start_recording
    authorize @event, :telemedicine_join?

    # AUDIT 2026-05-25 — `with_lock` cobre race do double-click: sem ele,
    # 2 cliques rapidíssimos (ou 2 abas) viam `active_rec=nil` cada um e
    # criavam 2 TelemedRecording com 3 egress jobs LiveKit cada — 6 jobs
    # pagos por consulta + 2× Whisper + 2× LLM evolução. Lock serializa
    # a leitura "já há recording ativo?" com a criação.
    result = @event.with_lock do
      Telemed::RecordingOrchestrator.new(event: @event).start!(force: true)
    end

    if result.started?
      render json: {
        data: {
          active:     true,
          started_at: result.recording&.created_at&.iso8601,
          recording_id: result.recording&.id
        }
      }
    elsif result.already_active?
      render json: {
        data: {
          active:     true,
          started_at: result.recording&.created_at&.iso8601,
          recording_id: result.recording&.id
        }
      }
    else
      reason = result.skipped_reason || 'unknown'
      render json: { error: friendly_recording_error(reason), code: reason.to_s },
             status: :unprocessable_entity
    end
  rescue Pundit::NotAuthorizedError
    raise
  rescue StandardError => e
    Rails.logger.error("[Telemed::Sessions#start_recording] #{e.class}: #{e.message}")
    render json: { error: 'Não foi possível iniciar a gravação.', code: 'recording_start_failed' },
           status: :internal_server_error
  end

  # POST /api/v1/accounts/:account_id/telemed/sessions/stop_recording?event_id=:id
  # Doutor clicou de novo no botão "Gravar" (já estava ON) → para.
  def stop_recording
    authorize @event, :telemedicine_join?

    recording = @event.telemed_recordings
                      .where(status: %w[pending recording])
                      .order(created_at: :desc)
                      .first

    if recording.nil?
      return render json: { data: { active: false } }
    end

    Telemed::RecordingOrchestrator.new(event: @event).stop!(recording)
    render json: { data: { active: false, recording_id: recording.id } }
  rescue Pundit::NotAuthorizedError
    raise
  rescue StandardError => e
    Rails.logger.error("[Telemed::Sessions#stop_recording] #{e.class}: #{e.message}")
    render json: { error: 'Não foi possível parar a gravação.', code: 'recording_stop_failed' },
           status: :internal_server_error
  end

  # POST /api/v1/accounts/:account_id/telemed/sessions/confirm_completed?event_id=:id
  # Doutor confirmou (via modal pós-encerramento) que de fato atendeu o paciente.
  # Marca o evento como 'completed' — única forma de chegar nesse status agora
  # que `SessionEventHandler#left!` não auto-transiciona mais.
  #
  # Idempotente: chamar 2x não erra; StatusTransition aceita
  # completed → completed como no-op.
  def confirm_completed
    authorize @event, :telemedicine_join?

    Telemed::StatusTransition.new(@event).mark_completed!(source: 'doctor_confirmed')

    render json: {
      data: {
        event_id: @event.id,
        status:   @event.reload.status
      }
    }
  rescue Pundit::NotAuthorizedError
    raise
  rescue StandardError => e
    Rails.logger.error("[Telemed::Sessions#confirm_completed] #{e.class}: #{e.message}")
    render json: { error: 'Não foi possível confirmar o atendimento.', code: 'telemedicine_confirm_failed' },
           status: :internal_server_error
  end

  private

  # Mensagens human-readable pros motivos do orchestrator pular start.
  # `participants_not_ready` é o caso mais comum (LiveKit ainda não
  # propagou presença); o front mostra a mensagem direto.
  def friendly_recording_error(reason)
    case reason.to_s
    when 'consent_missing'
      'O paciente ainda não aceitou o termo de gravação. Peça pra ele aceitar no preflight.'
    when 'participants_not_ready'
      'Aguarde o paciente entrar de fato na sala antes de gravar.'
    when 'audio_track_missing'
      'Microfone do paciente não foi detectado. Peça pra ele ativar o microfone (permissão do navegador) e tente de novo.'
    when 'doctor_audio_missing'
      'Seu microfone não foi detectado. Verifique a permissão no navegador e tente de novo.'
    when 'recording_disabled'
      'Gravação não está habilitada nesta conta.'
    else
      'Não foi possível iniciar a gravação agora.'
    end
  end

  # Aceita ID numérico OU slug `pppp-eeee-aaaa` (rota legada da agenda).
  def load_event
    raw = params[:event_id].presence || params[:id]
    @event = Current.account.agenda_events.find(resolve_event_id(raw))
  end

  def resolve_event_id(value)
    return value unless Telemed::RoomCode.slug?(value)

    parsed = Telemed::RoomCode.parse(value)
    parsed ? parsed[:event_id] : value
  end
end
