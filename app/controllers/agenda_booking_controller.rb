class AgendaBookingController < ActionController::Base
  layout 'agenda_booking'

  def show
    @public_id = params[:public_id]

    begin
      @user = User.joins(:beclinic_profile).find_by!(beclinic_user_profiles: { agenda_public_id: @public_id })
      @account = @user.accounts.first
      @config = @account.agenda_online_config

      unless @config&.enabled
        @error = 'disabled'
        return
      end
    rescue ActiveRecord::RecordNotFound
      @error = 'not_found'
    end
  end
end
