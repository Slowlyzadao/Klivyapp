class CreateAgendaServices < ActiveRecord::Migration[7.1]
  def change
    create_table :agenda_services do |t|
      t.string :name, null: false
      t.integer :duration_minutes, null: false, default: 60
      t.decimal :price, precision: 10, scale: 2, default: 0
      t.boolean :requires_room, null: false, default: false
      t.string :color, default: '#3b82f6'
      t.integer :position, default: 0
      t.references :account, null: false, foreign_key: true

      t.timestamps
    end

    add_index :agenda_services, [:account_id, :position]
  end
end
