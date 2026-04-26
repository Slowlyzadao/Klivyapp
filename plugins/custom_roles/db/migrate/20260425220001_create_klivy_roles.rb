class CreateKlivyRoles < ActiveRecord::Migration[7.0]
  def change
    create_table :klivy_roles do |t|
      t.references :account, null: false, foreign_key: true, index: true
      t.string  :name, null: false, limit: 80
      t.string  :description, limit: 240
      t.string  :preset_key, limit: 40
      t.jsonb   :permissions, null: false, default: {}
      t.timestamps
    end

    add_index :klivy_roles, [:account_id, :name], unique: true,
              name: 'index_klivy_roles_on_account_and_name'
  end
end
