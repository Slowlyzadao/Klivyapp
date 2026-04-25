class CreateTreatmentItems < ActiveRecord::Migration[7.0]
  def change
    create_table :treatment_items do |t|
      t.bigint  :account_id,              null: false
      t.bigint  :treatment_plan_id,       null: false
      t.string  :procedure_code
      t.string  :procedure_name,          null: false
      t.string  :region
      t.string  :tooth_number
      t.integer :sessions_planned,        null: false, default: 1
      t.integer :sessions_done,           null: false, default: 0
      t.decimal :unit_price,              precision: 10, scale: 2
      t.decimal :total_price,             precision: 10, scale: 2
      t.string  :priority
      # proposto / aprovado / em_execucao / concluido / cancelado
      t.string  :status,                  null: false, default: 'proposto'
      t.text    :clinical_justification
      t.text    :notes
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :treatment_items, :treatment_plan_id
    add_index :treatment_items, :account_id
    add_index :treatment_items, :status
    add_index :treatment_items, :deleted_at
  end
end
