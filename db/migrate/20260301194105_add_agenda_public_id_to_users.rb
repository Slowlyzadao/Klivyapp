class AddAgendaPublicIdToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :agenda_public_id, :string
    add_index :users, :agenda_public_id, unique: true
  end
end
