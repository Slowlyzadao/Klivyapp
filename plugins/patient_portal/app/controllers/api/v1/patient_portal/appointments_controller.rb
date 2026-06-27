# Consultas do paciente. Lista, detalhe e ações (confirmar presença / cancelar).
# Toda a query passa por PatientPortal::AppointmentVisibility — não duplica
# filtro de escopo em vários lugares.
class Api::V1::PatientPortal::AppointmentsController < Api::V1::PatientPortal::BaseController
  before_action :load_event, only: [:show, :confirm, :cancel]

  def index
    vis = PatientPortal::AppointmentVisibility.new(patient: current_patient, account: current_account)
    render json: {
      data: {
        upcoming: vis.upcoming.map { |e| serialize_event(e) },
        past:     vis.past.map     { |e| serialize_event(e) }
      }
    }
  end

  def show
    render json: { data: serialize_event(@event, detailed: true) }
  end

  # POST /api/v1/patient_portal/appointments/:id/confirm
  # Move `scheduled` → `confirmed`. Não muda outros estados (a clínica é dona).
  def confirm
    return render_error('Esta consulta não pode ser confirmada agora.') unless @event.status == 'scheduled'
    return render_error('Esta consulta já passou.') if @event.starts_at < Time.current

    @event.update!(status: 'confirmed')
    log!('confirm', @event)
    render json: { data: serialize_event(@event) }
  end

  # POST /api/v1/patient_portal/appointments/:id/cancel
  # Respeita `rescheduling.cancel_window_hours` do PatientPortalSetting.
  #
  # Sprint H — Comportamento por opt-in da clínica:
  #   - Se `financial.late_cancel_auto_invoice` = false (default): mantém o
  #     bloqueio histórico fora da janela.
  #   - Se = true: permite cancelar a qualquer momento, mas dispara
  #     LateCancelFeeAssessor → fee aparece no financeiro do paciente.
  def cancel
    return render_error('Esta consulta já foi cancelada.') if @event.discarded?
    return render_error('Esta consulta já passou.') if @event.starts_at < Time.current

    cutoff_hours = resolver.get(:rescheduling, :cancel_window_hours).presence || 24
    within_window = @event.starts_at < Time.current + cutoff_hours.to_i.hours
    auto_invoice  = current_account.patient_portal_setting&.financial&.dig('late_cancel_auto_invoice') == true

    if within_window && !auto_invoice
      return render_error("Cancelamento online só até #{cutoff_hours}h antes. Entre em contato com a clínica.",
                          status: :unprocessable_entity, code: 'cancel_window_passed')
    end

    @event.soft_delete!(actor: nil, reason: 'cancelamento_paciente', note: params[:reason].presence)

    fee_result = PatientPortal::Fees::LateCancelFeeAssessor.new(
      appointment: @event, actor: current_patient
    ).call

    log!('cancel', @event)
    render json: {
      data: serialize_event(@event),
      meta: { fee: fee_result.to_h }
    }
  end

  private

  def load_event
    vis = PatientPortal::AppointmentVisibility.new(patient: current_patient, account: current_account)
    @event = vis.find(resolve_event_id(params[:id]))
  end

  # Aceita tanto ID numérico quanto slug `pppp-eeee-aaaa` (Sprint K).
  # Sem esta resolução, `vis.find('17-284-76')` chamaria `.find` no Rails,
  # que faz `to_i` e pegaria só o '17' (perigoso — abriria evento errado).
  def resolve_event_id(value)
    return value unless Telemed::RoomCode.slug?(value)

    parsed = Telemed::RoomCode.parse(value)
    # Slug malformado → cai no find original (vai 404 limpo).
    parsed ? parsed[:event_id] : value
  end

  def resolver
    @resolver ||= PatientPortal::ConfigResolver.new(account: current_account, professional: @event&.user)
  end

  def serialize_event(e, detailed: false)
    cancel_cutoff = (resolver.get(:rescheduling, :cancel_window_hours).presence || 24).to_i.hours
    cutoff_time   = Time.current + cancel_cutoff
    can_confirm = e.status == 'scheduled' && !e.discarded? && e.starts_at >= Time.current
    can_cancel  = !e.discarded? && %w[scheduled confirmed].include?(e.status) && e.starts_at >= cutoff_time

    # Sprint J — Telemedicina (botão portal-side). URL configurada pela clínica
    # em AgendaEvent.custom_attributes (futuro: integração com LiveKit).
    telemed = Telemed::Session.new(event: e, account: current_account).call

    {
      id:               e.id,
      title:            e.title,
      status:           e.status,
      starts_at:        e.starts_at,
      ends_at:          e.ends_at,
      cancelled:        e.discarded?,
      cancelled_at:     e.deleted_at,
      cancellation_reason: e.deletion_reason,
      professional:     e.user          ? { id: e.user.id, name: e.user.name } : nil,
      service:          e.agenda_service ? { id: e.agenda_service.id, name: e.agenda_service.name } : nil,
      can_confirm:      can_confirm,
      can_cancel:       can_cancel,
      description:      detailed ? e.description : nil,
      telemedicine:     telemed.to_h
    }
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
