class CreateAnamneses < ActiveRecord::Migration[7.0]
  def change
    create_table :anamneses do |t|
      t.bigint   :patient_id,            null: false
      t.bigint   :account_id,            null: false
      t.bigint   :professional_id
      t.bigint   :form_template_id
      t.integer  :version_number,        default: 1,  null: false
      t.string   :specialty
      t.text     :chief_complaint
      t.jsonb    :medical_history,       default: {}
      t.jsonb    :allergies,             default: []
      t.jsonb    :current_medications,   default: []
      t.text     :surgical_history
      t.text     :family_history
      t.jsonb    :pregnancy,             default: {}
      t.jsonb    :relevant_habits,       default: {}
      t.jsonb    :contraindications,     default: []
      t.text     :additional_notes
      # status: draft → finalized (imutável após finalização)
      t.string   :status,                default: 'draft', null: false
      t.datetime :finalized_at
      t.datetime :deleted_at
      t.timestamps
    end

    add_index :anamneses, :patient_id
    add_index :anamneses, :account_id
    add_index :anamneses, :professional_id
    add_index :anamneses, :status
    add_index :anamneses, :deleted_at
    add_index :anamneses, [:patient_id, :version_number],
              name: 'index_anamneses_on_patient_id_and_version_number'
    add_index :anamneses, [:patient_id, :status, :deleted_at],
              name: 'index_anamneses_on_patient_status_deleted'

    add_foreign_key :anamneses, :accounts
    add_foreign_key :anamneses, :patients
  end
end
