class CreateAgendaServiceUsers < ActiveRecord::Migration[7.1]
  def change
    create_table :agenda_service_users do |t|
      t.references :account,          null: false, foreign_key: true
      t.references :agenda_service,   null: false, foreign_key: { to_table: :agenda_services }
      t.references :user,             null: false, foreign_key: true
      t.timestamps
    end

    add_index :agenda_service_users, [:agenda_service_id, :user_id],
              unique: true, name: 'idx_agenda_service_users_unique'
  end
end
