# Pedidos de agendamento criados pelo paciente. Index lista os do próprio
# paciente; create cria um novo; destroy cancela um pendente.
class Api::V1::PatientPortal::AppointmentRequestsController < Api::V1::PatientPortal::BaseController
  def index
    requests = PortalAppointmentRequest.for_patient(current_patient.id)
                                       .where(account_id: current_account.id)
                                       .recent_first
                                       .limit(20)
    render json: { data: requests.map { |r| serialize(r) } }
  end

  def create
    # Sprint H — bloqueio progressivo por inadimplência.
    restriction = PatientPortal::OverdueRestrictionChecker.new(
      account: current_account, patient: current_patient
    ).call
    if restriction.blocks_scheduling?
      return render_error(
        "Você tem pendências financeiras. Quite suas parcelas para voltar a agendar.",
        status: :unprocessable_entity, code: 'overdue_blocks_scheduling'
      )
    end

    record = PortalAppointmentRequest.new(
      account:                current_account,
      patient:                current_patient,
      preferred_professional_id: param_or_nil(:preferred_professional_id),
      preferred_service_id:   param_or_nil(:preferred_service_id),
      preferred_dates:        Array(params[:preferred_dates]).compact_blank.first(3),
      preferred_period:       params[:preferred_period].presence,
      notes:                  params[:notes].to_s.strip.presence,
      status:                 'pending'
    )

    if record.save
      log!('create', record)
      render json: { data: serialize(record) }, status: :created
    else
      render_error(record.errors.full_messages.join('; '))
    end
  end

  def destroy
    record = PortalAppointmentRequest.where(account_id: current_account.id,
                                             patient_id: current_patient.id).find(params[:id])
    return render_error('Pedido não pode mais ser cancelado.') unless record.cancelable_by_patient?

    record.update!(status: 'cancelled', processed_at: Time.current,
                   processed_notes: params[:reason].to_s.strip.presence)
    log!('cancel', record)
    render json: { data: serialize(record) }
  end

  private

  def param_or_nil(key)
    v = params[key]
    v.blank? ? nil : v
  end

  def serialize(r)
    {
      id:                  r.id,
      status:              r.status,
      created_at:          r.created_at,
      preferred_dates:     r.preferred_dates,
      preferred_period:    r.preferred_period,
      notes:               r.notes,
      preferred_professional: r.preferred_professional ? { id: r.preferred_professional.id, name: r.preferred_professional.name } : nil,
      preferred_service:   r.preferred_service ? { id: r.preferred_service.id, name: r.preferred_service.name } : nil,
      processed_at:        r.processed_at,
      processed_notes:     r.processed_notes,
      agenda_event_id:     r.agenda_event_id
    }
  end

  def log!(action, record)
    PatientPortalAccessLog.log!(
      account: current_account, patient: current_patient,
      action: action, resource: record,
      ip: request.remote_ip, user_agent: request.user_agent,
      metadata: { status: record.status }
    )
  end
end
