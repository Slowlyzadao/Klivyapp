class AddShowOnlyWorkingHoursToAgendaSettings < ActiveRecord::Migration[7.1]
  def change
    add_column :agenda_settings, :show_only_working_hours, :boolean, default: false, null: false
  end
end
