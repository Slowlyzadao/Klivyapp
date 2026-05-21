class CreateAgendaSettings < ActiveRecord::Migration[7.1]
  def change
    create_table :agenda_settings do |t|
      t.bigint :account_id, null: false
      t.boolean :block_outside_working_hours, default: false, null: false
      t.boolean :block_lunch_break, default: false, null: false
      t.jsonb :week_days, default: [], null: false
      t.jsonb :exceptions, default: [], null: false
      t.jsonb :holidays, default: [], null: false
      t.timestamps
    end

    add_index :agenda_settings, :account_id, unique: true
  end
end
