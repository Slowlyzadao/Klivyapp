class AddVisibleHoursBufferToAgendaSettings < ActiveRecord::Migration[7.1]
  def change
    add_column :agenda_settings, :visible_hours_buffer, :integer, default: 2, null: false
  end
end
