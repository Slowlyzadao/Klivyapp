class AgendaBookingController < ActionController::Base
  layout 'agenda_booking'

  def show
    @public_id = params[:public_id]

    begin
      @user = User.joins(:beclinic_profile).find_by!(beclinic_user_profiles: { agenda_public_id: @public_id })
      @account = @user.accounts.first
      @config = @account.agenda_online_config
      @agenda_setting = @account.agenda_setting

      # Branding pulled from installation-wide GlobalConfig (same source the
      # dashboard uses for `LOGO` / `BRAND_NAME`). Falls back to safe
      # defaults so the page never renders broken if a config is missing.
      @brand_name = GlobalConfigService.load('BRAND_NAME', 'Klivy')
      @brand_logo = GlobalConfigService.load('LOGO', '/brand-assets/logo.svg')
      @brand_logo_dark = GlobalConfigService.load('LOGO_DARK', '/brand-assets/logo_dark.svg')

      unless @config&.enabled
        @error = 'disabled'
        return
      end
    rescue ActiveRecord::RecordNotFound
      @error = 'not_found'
    end
  end
end
