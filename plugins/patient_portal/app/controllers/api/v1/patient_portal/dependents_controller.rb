# Dependentes do paciente logado (Sprint I, PRD §13.2).
#
# Endpoints:
#   GET    /api/v1/patient_portal/dependents
#     → lista dos patients que o logado pode acessar (self + dependentes ativos)
#   POST   /api/v1/patient_portal/dependents/switch
#     → muda active_patient_id da sessão; subsequentes requests veem dados do
#       dependente. Body: { patient_id: <int> }
#
# Toda a regra de "pode acessar quem?" mora em `PatientPortal::SessionContext`.
class Api::V1::PatientPortal::DependentsController < Api::V1::PatientPortal::BaseController
  def index
    ctx = PatientPortal::SessionContext.new(session: current_session).resolve
    render json: { data: ctx.to_h }
  end

  def switch
    target = Patient.find_by(id: params[:patient_id], account_id: current_account.id)
    return render_error('Paciente alvo inválido.', status: :not_found, code: 'not_found') if target.blank?

    ctx_service = PatientPortal::SessionContext.new(session: current_session)
    unless ctx_service.can_act_on?(target)
      return render_error('Você não tem permissão para acessar este paciente.',
                          status: :forbidden, code: 'forbidden')
    end

    current_session.update!(active_patient_id: target.id)
    log!('dependent_switch', target)

    render json: {
      data: PatientPortal::SessionContext.new(session: current_session.reload).resolve.to_h
    }
  end

  private

  def log!(action, target)
    PatientPortalAccessLog.log!(
      account: current_account, patient: current_acting_patient,
      action: action,
      resource: target,
      ip: request.remote_ip, user_agent: request.user_agent,
      metadata: { acting_patient_id: current_acting_patient.id, active_patient_id: target.id }
    )
  end
end
