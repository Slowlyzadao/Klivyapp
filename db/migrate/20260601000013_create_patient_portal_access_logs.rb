# Trilha de auditoria de todo acesso/ação do paciente no portal. PRD §17.1
# (LGPD obrigatório). Sem isso, fica impossível responder pedido de informação.
#
# `action` enum textual aberta — adicionamos novos tipos conforme features crescem
# (login, view, download, sign, revoke, message, suspension_change, etc.).
class CreatePatientPortalAccessLogs < ActiveRecord::Migration[7.1]
  def change
    create_table :patient_portal_access_logs do |t|
      t.references :account, null: false, foreign_key: true
      t.references :patient, null: false, foreign_key: true

      t.string :action, null: false

      # Recurso afetado (polimórfico textual — não usamos belongs_to polymorphic
      # porque o paciente nunca dispara delete cascading via essa relação).
      t.string :resource_type
      t.bigint :resource_id

      t.string :ip
      t.string :user_agent
      t.jsonb :metadata, null: false, default: {}

      # Particionamento por created_at é boa ideia (LGPD logs crescem rápido) —
      # mantém simples no MVP, F2 pode adotar pg_partman.
      t.datetime :created_at, null: false

      t.index [:patient_id, :created_at]
      t.index [:account_id, :action, :created_at], name: 'idx_pp_access_logs_account_action_at'
    end
  end
end
