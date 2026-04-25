class Api::V1::Accounts::Patients::CriticalAlertsController < Api::V1::Accounts::BaseController
  before_action :fetch_patient
  before_action :fetch_alert, only: [:update, :destroy, :deactivate]
  before_action :check_authorization

  # GET /api/v1/accounts/:account_id/patients/:patient_id/critical_alerts
  def index
    @critical_alerts = CriticalAlert.where(patient: @patient, account: current_account)
                                    .active
                                    .ordered_by_severity
                                    .includes(:created_by)

    render 'api/v1/accounts/patients/critical_alerts/index', format: :json
  end

  # POST /api/v1/accounts/:account_id/patients/:patient_id/critical_alerts
  def create
    @critical_alert = CriticalAlert.new(
      alert_params.merge(patient: @patient, account: current_account, created_by: current_user)
    )
    authorize @critical_alert

    if @critical_alert.save
      PatientAuditLog.log!(
        account: current_account,
        patient: @patient,
        action: 'create',
        actor: current_user,
        resource: @critical_alert,
        ip_address: request.remote_ip
      )
      render 'api/v1/accounts/patients/critical_alerts/show', format: :json, status: :created
    else
      render json: { errors: @critical_alert.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # PATCH /api/v1/accounts/:account_id/patients/:patient_id/critical_alerts/:id
  def update
    authorize @critical_alert

    if @critical_alert.update(alert_params)
      render 'api/v1/accounts/patients/critical_alerts/show', format: :json
    else
      render json: { errors: @critical_alert.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # DELETE /api/v1/accounts/:account_id/patients/:patient_id/critical_alerts/:id
  def destroy
    authorize @critical_alert

    @critical_alert.soft_delete!
    head :ok
  end

  # PATCH /api/v1/accounts/:account_id/patients/:patient_id/critical_alerts/:id/deactivate
  def deactivate
    authorize @critical_alert

    @critical_alert.deactivate!
    render json: { active: false }, status: :ok
  end

  private

  def fetch_patient
    @patient = current_account.patients.find(params[:patient_id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Paciente não encontrado' }, status: :not_found
  end

  def fetch_alert
    @critical_alert = CriticalAlert.where(patient: @patient, account: current_account)
                                   .active
                                   .find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Alerta não encontrado' }, status: :not_found
  end

  def alert_params
    params.require(:critical_alert).permit(:alert_type, :severity, :title, :description, :active)
  end
end
