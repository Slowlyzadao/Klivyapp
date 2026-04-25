class Api::V1::Accounts::Patients::AuditLogsController < Api::V1::Accounts::Patients::BaseController
  # GET /api/v1/accounts/:account_id/patients/:patient_id/audit_logs
  def index
    @audit_logs = PatientAuditLog.where(patient: @patient, account: current_account)
                                 .ordered
                                 .page(page_number).per(page_size)

    @audit_logs = filter_logs(@audit_logs)

    render json: {
      audit_logs: @audit_logs.map { |log| serialize_log(log) },
      meta: {
        total_count: @audit_logs.total_count,
        current_page: @audit_logs.current_page,
        total_pages: @audit_logs.total_pages
      }
    }, status: :ok
  end

  # GET /api/v1/accounts/:account_id/patients/:patient_id/audit_logs/export
  def export
    authorize @patient, :export?

    result = ::Patients::RecordPdfGenerator.call(
      patient: @patient,
      generated_by: current_user,
      ip_address: request.remote_ip
    )

    if result.success?
      send_data result.pdf_data,
                filename: "prontuario_paciente_#{@patient.id}_#{Time.current.strftime('%Y%m%d%H%M')}.pdf",
                type: 'application/pdf',
                disposition: 'attachment'
    else
      render json: { error: 'Falha ao gerar o PDF do prontuário', details: result.error }, status: :unprocessable_entity
    end
  end

  private

  def check_authorization
    true
  end

  def fetch_patient
    @patient = current_account.patients.find(params[:patient_id])
    authorize @patient, :audit_logs?
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Paciente não encontrado' }, status: :not_found
  end

  def filter_logs(scope)
    scope = scope.by_action(params[:action_type]) if params[:action_type].present?
    scope = scope.by_actor(params[:actor_id]) if params[:actor_id].present?
    if params[:start_date].present? && params[:end_date].present?
      scope = scope.where(occurred_at: Date.parse(params[:start_date]).beginning_of_day..Date.parse(params[:end_date]).end_of_day)
    end
    scope
  end

  def serialize_log(log)
    {
      id: log.id,
      action: log.action,
      actor_id: log.actor_id,
      actor_name: log.actor_name,
      actor_role: log.actor_role,
      resource_type: log.resource_type,
      resource_id: log.resource_id,
      changed_fields: log.changed_fields,
      old_value: log.old_value,
      new_value: log.new_value,
      ip_address: log.ip_address,
      occurred_at: log.occurred_at.iso8601
    }
  end

  def page_number
    params[:page] || 1
  end

  def page_size
    [params[:per_page].to_i, 100].min.then { |n| n.zero? ? 25 : n }
  end
end
