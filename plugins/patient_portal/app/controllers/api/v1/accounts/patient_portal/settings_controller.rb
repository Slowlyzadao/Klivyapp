# CRUD do PatientPortalSetting (uma linha por account). PRD §14.7.
# Endpoint `apply_preset` aplica o preset "Autonomia Guiada" no MVP.
class Api::V1::Accounts::PatientPortal::SettingsController < Api::V1::Accounts::PatientPortal::BaseController
  def show
    render json: { data: serialize(setting_or_initialize) }
  end

  def update
    setting = setting_or_initialize
    setting.assign_attributes(permitted_params)
    setting.save!
    render json: { data: serialize(setting) }
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: [{ code: 'invalid', message: e.message }] }, status: :unprocessable_entity
  end

  # POST /api/v1/accounts/:account_id/patient_portal/setting/apply_preset
  def apply_preset
    setting = setting_or_initialize
    PatientPortal::PresetApplier.new(setting: setting, preset_key: params[:preset_key] || 'autonomy_guided').call
    render json: { data: serialize(setting) }
  rescue ArgumentError => e
    render json: { errors: [{ code: 'invalid_preset', message: e.message }] }, status: :unprocessable_entity
  end

  private

  def setting_or_initialize
    Current.account.patient_portal_setting || Current.account.create_patient_portal_setting!
  end

  def permitted_params
    params.require(:setting).permit(
      :active_preset, :default_inbox_id, :appointment_request_inbox_id,
      :document_request_inbox_id, :compliance_inbox_id, :urgent_inbox_id,
      scheduling: {}, rescheduling: {}, financial: {}, documents: {},
      clinical: {}, messaging: {}, engagement: {}, invite: {},
      business_hours: {}, notification_events_enabled: {}
    )
  end

  def serialize(setting)
    setting.as_json(except: [:created_at, :updated_at])
  end
end
