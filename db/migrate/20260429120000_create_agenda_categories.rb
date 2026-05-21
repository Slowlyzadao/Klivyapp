class CreateAgendaCategories < ActiveRecord::Migration[7.1]
  def change
    create_table :agenda_categories do |t|
      t.string :name, null: false
      t.string :color, null: false, default: '#3b82f6'
      t.integer :position, null: false, default: 0
      t.boolean :active, null: false, default: true
      t.references :account, null: false, foreign_key: true

      t.timestamps
    end

    add_index :agenda_categories, [:account_id, :name], unique: true
    add_index :agenda_categories, [:account_id, :position]
  end
end
