class Api::V1::Accounts::Patients::ExamFoldersController < Api::V1::Accounts::BaseController
  before_action :set_patient
  before_action :ensure_view_exams!, only: [:index]
  before_action :ensure_manage_exams!, only: [:update]

  # GET — returns the full folder data blob for this patient
  def index
    render json: (@patient.exam_folder_data || {})
  end

  # PUT /bulk — saves the entire folder structure as a JSON blob
  def update
    @patient.update!(exam_folder_data: sanitized_folder_data)
    render json: @patient.exam_folder_data
  end

  private

  def ensure_view_exams!
    return if Current.user.beclinic_can?(Current.account, :patients, :view_exams)

    render json: { error: 'Acesso negado' }, status: :forbidden
  end

  def ensure_manage_exams!
    return if Current.user.beclinic_can?(Current.account, :patients, :manage_exams)

    render json: { error: 'Você não tem permissão para gerenciar exames' }, status: :forbidden
  end

  def set_patient
    @patient = Current.account.patients.find(params[:patient_id])
  end

  def folder_data_params
    params.permit(
      folders: [:id, :name, :color, :isRoot, :parent_id, :position],
      lock_map: {},
      media_folder_map: {},
      expanded_ids: []
    ).to_h
  end

  # Filtra media_folder_map e lock_map para só aceitar IDs de medias
  # que pertencem a este paciente (evita persistir IDs cross-tenant/inexistentes).
  def sanitized_folder_data
    raw = folder_data_params
    valid_media_ids = @patient.exam_medias.active.pluck(:id).map(&:to_s).to_set

    raw['media_folder_map'] = (raw['media_folder_map'] || {}).select do |media_id, _folder_id|
      valid_media_ids.include?(media_id.to_s)
    end
    raw['lock_map'] = (raw['lock_map'] || {}).select do |media_id, _locked|
      valid_media_ids.include?(media_id.to_s)
    end
    raw
  end
end
