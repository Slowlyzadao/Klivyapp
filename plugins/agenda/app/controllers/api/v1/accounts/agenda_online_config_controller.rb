class Api::V1::Accounts::AgendaOnlineConfigController < Api::V1::Accounts::BaseController
  before_action :fetch_config, only: [:show, :update]

  def show
    render json: @config
  end

  def update
    if @config.update(config_params)
      render json: @config
    else
      render_error_response(@config.errors.full_messages.to_sentence)
    end
  end

  private

  def fetch_config
    @config = Current.account.agenda_online_config || Current.account.create_agenda_online_config(form_fields: AgendaOnlineConfig.default_form_fields)
  end

  def config_params
    params.require(:agenda_online_config).permit(
      :enabled,
      :allow_new_patients,
      :require_whatsapp_verification,
      :require_email_verification,
      :min_lead_time_minutes,
      :future_limit_days,
      form_fields: [:id, :label, :type, :required, :system]
    )
  end
end
