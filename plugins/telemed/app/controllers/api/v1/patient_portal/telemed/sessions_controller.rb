# Token JWT + reportagem de joined/left para o lado PACIENTE da sala.
#
# Antes: actions `telemedicine_token`/`telemedicine_event` viviam em
# `appointments_controller`. Extraídas pra cá quando o módulo virou plugin
# próprio. Mesma lógica do controller equivalente do dentista, mas com
# role='patient' e acesso via PatientPortal session (sem account_id no path).
class Api::V1::PatientPortal::Telemed::SessionsController < Api::V1::PatientPortal::BaseController
  before_action :load_event

  # POST /api/v1/patient_portal/telemed/sessions?event_id=:id
  #
  # 2026-05-21 — Waiting room SERVER-SIDE.
  # Paciente sempre entra com `canPublish: false`. Doutor precisa chamar
  # `admit_patient` (admin) pra liberar publish via LiveKit UpdateParticipant.
  # `outside_window` continua sendo retornado pra UX mostrar "sua consulta é
  # daqui a X min" — mas NÃO é mais o que controla a sala de espera.
  def create
    telemed = Telemed::Session.new(event: @event, account: current_account).call

    if telemed.permanently_blocked?
      reason_code = telemed.enabled? ? telemed.reason : 'telemedicine_not_enabled'
      return render_error('Esta consulta não está mais disponível para teleconsulta.',
                          status: :unprocessable_entity, code: reason_code)
    end

    # `current_acting_patient` = quem realmente está logado (responsável OU paciente).
    # Cada participante precisa de identity ÚNICA. Quando um responsável entra
    # atuando como dependente, identidades distintas evitam confusão no LiveKit.
    #
    # 2026-05-21 — Reidratação de admissão: se o paciente já foi admitido
    # nesta sala antes (F5, reconexão, troca de aba), pula o waiting room
    # e emite token JÁ admitido. Sem isso, paciente que recarregava a
    # página caía de novo na fila do dentista — atrito desnecessário no
    # meio de uma consulta.
    already_admitted = patient_already_admitted?(@event, current_acting_patient)

    session = Telemed::SessionIssuer.new(
      event:       @event,
      participant: current_acting_patient,
      role:        'patient',
      admitted:    already_admitted
    ).call

    log!('telemedicine_join', @event)
    render json: {
      data: session.to_h.merge(
        outside_window:    telemed.outside_window?,
        starts_in_seconds: telemed.starts_in_seconds,
        ends_in_seconds:   telemed.ends_in_seconds,
        window_reason:     telemed.reason
      )
    }
  rescue StandardError => e
    Rails.logger.error("[PatientPortal::Telemed::Sessions#create] #{e.class} #{e.message}")
    render_error('Não foi possível gerar o acesso à sala. Tente novamente.',
                 status: :internal_server_error, code: 'telemedicine_issue_failed')
  end

  # POST /api/v1/patient_portal/telemed/sessions/event?event_id=:id&kind=joined|left
  # Frontend reporta `joined` / `left` da sala LiveKit.
  # Aciona SessionEventHandler que decide transição de status + jobs.
  def event
    kind = params[:kind].to_s
    return render_error('Tipo de evento inválido.', status: :unprocessable_entity) \
      unless %w[joined left].include?(kind)

    # Paciente pode ter aceitado o termo de gravação no preflight.
    # Persistimos ANTES do handler rodar pra que o RecordingOrchestrator
    # (chamado dentro de joined!) já enxergue o consent.
    persist_recording_consent! if kind == 'joined' && params[:recording_consent].to_s == 'true'

    handler = Telemed::SessionEventHandler.new(event: @event, role: 'patient')
    result = kind == 'joined' ? handler.joined! : handler.left!

    render json: {
      data: {
        event_id: @event.id,
        status:   @event.reload.status,
        session:  result.session.to_h,
        scheduled_jobs: result.scheduled_jobs
      }
    }
  rescue StandardError => e
    Rails.logger.error("[PatientPortal::Telemed::Sessions#event] #{e.class} #{e.message}")
    render_error('Não foi possível registrar o evento da sessão.',
                 status: :internal_server_error, code: 'telemedicine_event_failed')
  end

  private

  # Persiste o aceite do termo de gravação:
  #   (a) timestamp no `custom_attributes` do AgendaEvent (per-event)
  #   (b) row em TelemedConsent (per-patient — vale pra futuras consultas
  #       se a clínica configurar um termo único). Idempotente.
  def persist_recording_consent!
    @event.with_lock do
      attrs = (@event.custom_attributes || {}).deep_dup
      attrs['telemedicine_recording_consent_at'] = Time.current.iso8601
      @event.update!(custom_attributes: attrs)
    end

    patient = Patient.find_by(account_id: current_account.id, contact_id: @event.contact_id)
    return unless patient

    TelemedConsent.accept!(
      account:    current_account,
      patient:    patient,
      ip:         request.remote_ip,
      user_agent: request.user_agent
    )
  rescue StandardError => e
    # Falha não bloqueia entrada — orchestrator simplesmente não inicia gravação
    # se consent não persistir.
    Rails.logger.warn("[PatientPortal::Telemed::Sessions#event] consent persist falhou: #{e.class} #{e.message}")
  end

  # Checa se o patient_id atual já foi admitido pelo dentista anteriormente
  # E se essa admissão ainda é válida (dentro da janela do evento + status
  # não-final). Delegado pra Telemed::AdmissionWindow — mesmo helper que o
  # admin usa em `accounts/telemed/sessions#create`, garantindo critério
  # idêntico nos dois lados (admissão por nonce/identity teria divergido
  # outra vez se cada lado filtrasse com sua própria lógica).
  def patient_already_admitted?(event, patient)
    return false unless patient
    Telemed::AdmissionWindow.new(event: event).admitted?(patient_id: patient.id)
  end

  def load_event
    vis = PatientPortal::AppointmentVisibility.new(patient: current_patient, account: current_account)
    raw = params[:event_id].presence || params[:id]
    @event = vis.find(resolve_event_id(raw))
  end

  # Aceita tanto ID numérico quanto slug `pppp-eeee-aaaa`.
  def resolve_event_id(value)
    return value unless Telemed::RoomCode.slug?(value)

    parsed = Telemed::RoomCode.parse(value)
    parsed ? parsed[:event_id] : value
  end

  def log!(action, event)
    PatientPortalAccessLog.log!(
      account: current_account, patient: current_patient,
      action: action, resource: event,
      ip: request.remote_ip, user_agent: request.user_agent,
      metadata: { event_id: event.id, status: event.status }
    )
  end
end
