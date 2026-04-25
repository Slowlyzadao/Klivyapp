class CreateClinicalNotes < ActiveRecord::Migration[7.0]
  def change
    create_table :clinical_notes do |t|
      t.bigint   :patient_id,           null: false
      t.bigint   :account_id,           null: false
      t.bigint   :professional_id
      t.bigint   :appointment_id        # FK opcional para agenda_events
      t.bigint   :form_template_id
      t.date     :note_date,            null: false
      t.text     :complaint_of_day
      t.text     :assessment
      t.text     :conduct
      t.text     :complications
      t.text     :guidance_given
      t.date     :return_recommended
      # status: draft (editável por 48h) → signed (imutável para sempre)
      t.string   :status,               default: 'draft', null: false
      t.datetime :signed_at
      t.bigint   :signed_by_id
      t.datetime :deleted_at
      t.timestamps
    end

    add_index :clinical_notes, :patient_id
    add_index :clinical_notes, :account_id
    add_index :clinical_notes, :professional_id
    add_index :clinical_notes, :appointment_id
    add_index :clinical_notes, :note_date
    add_index :clinical_notes, :status
    add_index :clinical_notes, :deleted_at
    add_index :clinical_notes, :signed_by_id
    add_index :clinical_notes, [:patient_id, :note_date],
              name: 'index_clinical_notes_on_patient_id_and_note_date'
    add_index :clinical_notes, [:patient_id, :status, :deleted_at],
              name: 'index_clinical_notes_on_patient_status_deleted'

    add_foreign_key :clinical_notes, :accounts
    add_foreign_key :clinical_notes, :patients
  end
end
