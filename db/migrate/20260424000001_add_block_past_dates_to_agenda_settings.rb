class AddBlockPastDatesToAgendaSettings < ActiveRecord::Migration[7.1]
  def change
    add_column :agenda_settings, :block_past_dates, :boolean, default: false, null: false
  end
end
