# Suspensão/restauração do acesso de um paciente ao portal (PRD §5.7).
# POST   = suspender (com razão obrigatória e janela opcional)
# DELETE = restaurar (portal_status volta para 'active')
class Api::V1::Accounts::PatientPortal::PortalSuspensionsController < Api::V1::Accounts::PatientPortal::BaseController
  before_action :fetch_patient

  STATUS_VALUES = %w[suspended_temporary suspended_permanent restricted].freeze

  def create
    return render_error('Razão é obrigatória.') if params[:reason].blank?
    return render_error('status inválido.')     unless STATUS_VALUES.include?(params[:status])

    @patient.update!(
      portal_status:            params[:status],
      portal_suspension_reason: params[:reason],
      portal_suspended_until:   params[:until].presence
    )

    PatientPortalAccessLog.log!(
      account: Current.account, patient: @patient,
      action: 'suspension_change',
      ip: request.remote_ip, user_agent: request.user_agent,
      metadata: { status: params[:status], reason: params[:reason], until: params[:until] }
    )

    render json: { data: { portal_status: @patient.portal_status, portal_suspended_until: @patient.portal_suspended_until } }
  end

  def destroy
    @patient.update!(
      portal_status: 'active',
      portal_suspension_reason: nil,
      portal_suspended_until: nil
    )

    PatientPortalAccessLog.log!(
      account: Current.account, patient: @patient,
      action: 'suspension_change',
      ip: request.remote_ip, user_agent: request.user_agent,
      metadata: { status: 'active' }
    )

    render json: { data: { portal_status: 'active' } }
  end

  private

  def fetch_patient
    @patient = Current.account.patients.find(params[:patient_id])
  rescue ActiveRecord::RecordNotFound
    render json: { errors: [{ code: 'not_found', message: 'Paciente não encontrado.' }] }, status: :not_found
  end

  def render_error(message)
    render json: { errors: [{ code: 'invalid', message: message }] }, status: :unprocessable_entity
  end
end
