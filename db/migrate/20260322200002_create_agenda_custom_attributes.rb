class CreateAgendaCustomAttributes < ActiveRecord::Migration[7.1]
  def change
    create_table :agenda_custom_attributes do |t|
      t.bigint :account_id, null: false
      t.string :name, null: false
      t.string :field_type, default: 'text', null: false
      t.boolean :required, default: false, null: false
      t.boolean :validate_cpf, default: true, null: false
      t.text :options
      t.integer :position, default: 0, null: false
      t.timestamps
    end

    add_index :agenda_custom_attributes, [:account_id, :position], name: 'idx_agenda_custom_attrs_account_position'
    add_index :agenda_custom_attributes, :account_id
  end
end
