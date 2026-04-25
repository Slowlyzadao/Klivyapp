class Api::V1::Accounts::AgendaSettingsController < Api::V1::Accounts::BaseController
  before_action :check_authorization

  def show
    @setting = Current.account.agenda_setting || Current.account.build_agenda_setting
    render json: setting_payload
  end

  def update
    @setting = Current.account.agenda_setting || Current.account.build_agenda_setting
    @setting.assign_attributes(setting_params)
    @setting.save!
    render json: setting_payload
  end

  private

  def setting_payload
    {
      block_outside_working_hours: @setting.block_outside_working_hours,
      block_lunch_break: @setting.block_lunch_break,
      slot_interval_minutes: @setting.slot_interval_minutes,
      week_days: @setting.week_days,
      exceptions: @setting.exceptions,
      holidays: @setting.holidays
    }
  end

  def setting_params
    params.require(:agenda_setting).permit(
      :block_outside_working_hours,
      :block_lunch_break,
      :slot_interval_minutes,
      week_days: [:id, :label, :enabled, :start, :end, :lunchStart, :lunchEnd],
      exceptions: [:title, :type, :icon, :color, :start, :end],
      holidays: [:name, :date, :status]
    )
  end
end
