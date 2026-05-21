class CreateWaitingListEntries < ActiveRecord::Migration[7.0]
  def change
    create_table :waiting_list_entries do |t|
      t.references :account, null: false, foreign_key: true, index: true
      t.references :contact, null: false, foreign_key: true, index: true
      t.string :period, null: false
      t.string :specific_time
      t.jsonb :preferred_days, default: []
      t.text :notes

      t.timestamps
    end

    add_index :waiting_list_entries, [:account_id, :contact_id], unique: true
  end
end
