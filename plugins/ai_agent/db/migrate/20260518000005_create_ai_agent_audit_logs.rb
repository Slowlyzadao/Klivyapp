class CreateAiAgentAuditLogs < ActiveRecord::Migration[7.1]
  def change
    create_table :ai_agent_audit_logs do |t|
      t.bigint :super_admin_id
      t.bigint :user_id
      t.bigint :account_id
      t.string :scope, null: false
      t.string :action, null: false
      t.jsonb :changes_summary, null: false, default: {}
      t.string :ip_address
      t.datetime :created_at, null: false
    end

    add_index :ai_agent_audit_logs, :account_id
    add_index :ai_agent_audit_logs, :scope
    add_index :ai_agent_audit_logs, :created_at
  end
end
