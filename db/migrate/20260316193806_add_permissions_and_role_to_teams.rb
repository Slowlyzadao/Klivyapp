class AddPermissionsAndRoleToTeams < ActiveRecord::Migration[7.1]
  def change
    add_column :teams, :permissions, :jsonb, default: {}, null: false
    add_column :teams, :beclinic_role, :string, default: 'especialista', null: false
    add_column :teams, :is_preset, :boolean, default: false, null: false
  end
end
