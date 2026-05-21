class RenameChangesToChangedFieldsInPatientAuditLogs < ActiveRecord::Migration[7.1]
  def change
    rename_column :patient_audit_logs, :changes, :changed_fields
  end
end
