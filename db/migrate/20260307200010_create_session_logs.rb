class CreateSessionLogs < ActiveRecord::Migration[7.0]
  def change
    create_table :session_logs do |t|
      t.bigint   :account_id,              null: false
      t.bigint   :patient_id,              null: false
      t.bigint   :professional_id
      t.bigint   :treatment_plan_id
      t.bigint   :treatment_item_id
      t.bigint   :appointment_id           # FK para agenda_events
      t.datetime :performed_at,            null: false
      t.integer  :duration_minutes
      t.jsonb    :areas_treated,           null: false, default: []
      t.jsonb    :products_used,           null: false, default: []
      # Estrutura preparada para Estoque futuro:
      # [{ "product_id": 1, "name": "Produto X", "quantity": 2, "unit": "ml" }]
      t.text     :complications
      t.text     :result_observed
      t.text     :post_procedure_guidance
      t.boolean  :return_needed,           null: false, default: false
      t.integer  :return_in_days
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :session_logs, :account_id
    add_index :session_logs, :patient_id
    add_index :session_logs, :professional_id
    add_index :session_logs, :treatment_plan_id
    add_index :session_logs, :treatment_item_id
    add_index :session_logs, :appointment_id
    add_index :session_logs, :performed_at
    add_index :session_logs, :deleted_at
  end
end
