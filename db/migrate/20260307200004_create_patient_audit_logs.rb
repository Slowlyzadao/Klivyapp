class CreatePatientAuditLogs < ActiveRecord::Migration[7.0]
  def change
    create_table :patient_audit_logs do |t|
      t.bigint   :account_id,     null: false
      t.bigint   :patient_id,     null: false
      t.bigint   :actor_id        # user que executou a ação
      t.string   :actor_name      # snapshot do nome (não muda se user for excluído)
      t.string   :actor_role      # snapshot do papel no momento
      t.string   :action,         null: false  # view/create/update/delete/sign/export
      t.string   :resource_type   # ex: "Patient", "ClinicalNote", etc.
      t.bigint   :resource_id
      t.jsonb    :changes         # diff de atributos alterados
      t.jsonb    :old_value       # valor anterior (snapshot)
      t.jsonb    :new_value       # valor novo (snapshot)
      t.string   :ip_address
      t.string   :user_agent
      t.datetime :occurred_at,    null: false
      # NÃO TEM updated_at — log é IMUTÁVEL
      t.datetime :created_at,     null: false
    end

    add_index :patient_audit_logs, :patient_id
    add_index :patient_audit_logs, :account_id
    add_index :patient_audit_logs, :actor_id
    add_index :patient_audit_logs, :action
    add_index :patient_audit_logs, :occurred_at
    add_index :patient_audit_logs, [:resource_type, :resource_id]
    add_index :patient_audit_logs, [:patient_id, :occurred_at]
    add_index :patient_audit_logs, [:account_id, :occurred_at]

    add_foreign_key :patient_audit_logs, :accounts
    add_foreign_key :patient_audit_logs, :patients
  end
end
