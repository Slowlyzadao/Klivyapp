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
      role:        'doctor'
    ).call

    payload = session.to_h.merge(
      outside_window:    telemed.outside_window?,
      starts_in_seconds: telemed.starts_in_seconds,
      ends_in_seconds:   telemed.ends_in_seconds,
      window_reason:     telemed.reason
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

  private

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
