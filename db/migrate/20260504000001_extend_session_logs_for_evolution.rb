class ExtendSessionLogsForEvolution < ActiveRecord::Migration[7.0]
  def change
    change_table :session_logs, bulk: true do |t|
      t.text     :complaint_of_day
      t.text     :assessment
      t.text     :next_consultation_details
      t.text     :observation
      t.string   :status, null: false, default: 'draft'
      t.datetime :signed_at
      t.bigint   :signed_by_id
      t.datetime :erratum_at
      t.bigint   :erratum_by_id
      t.text     :erratum_reason
      t.integer  :lock_version, null: false, default: 0
      t.bigint   :form_template_id
      t.bigint   :migrated_from_clinical_note_id

      t.text     :patient_signature_blob
      t.string   :patient_signature_mode
      t.datetime :patient_signed_at
      t.string   :patient_signature_integrity_hash
      t.string   :patient_signature_remote_token
      t.datetime :patient_signature_remote_link_sent_at
      t.datetime :patient_signature_remote_link_expires_at
      t.string   :patient_signature_ip
      t.string   :patient_signature_device_info
    end

    add_index :session_logs, :signed_by_id
    add_index :session_logs, :erratum_by_id
    add_index :session_logs, :erratum_at
    add_index :session_logs, :form_template_id
    add_index :session_logs, %i[patient_id status deleted_at], name: 'idx_session_logs_patient_status'
    add_index :session_logs,
              :migrated_from_clinical_note_id,
              unique: true,
              where: 'migrated_from_clinical_note_id IS NOT NULL',
              name: 'idx_session_logs_migrated_from_clinical_note'
    add_index :session_logs,
              :patient_signature_remote_token,
              unique: true,
              where: 'patient_signature_remote_token IS NOT NULL',
              name: 'idx_session_logs_patient_signature_token'
  end
end
