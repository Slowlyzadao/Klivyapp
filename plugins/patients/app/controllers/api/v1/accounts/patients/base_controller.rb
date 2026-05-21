class Api::V1::Accounts::Patients::BaseController < Api::V1::Accounts::BaseController
  include BeclinicErrorResponse

  before_action :fetch_patient
  before_action :check_authorization

  private

  def fetch_patient
    @patient = Current.account.patients.find(params[:patient_id])
  rescue ActiveRecord::RecordNotFound
    render_error('Paciente não encontrado', status: :not_found)
  end
end
