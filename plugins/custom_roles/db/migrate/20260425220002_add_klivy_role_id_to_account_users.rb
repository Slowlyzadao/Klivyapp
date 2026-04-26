class AddKlivyRoleIdToAccountUsers < ActiveRecord::Migration[7.0]
  def change
    add_reference :account_users, :klivy_role,
                  null: true, foreign_key: { to_table: :klivy_roles },
                  index: true
  end
end
