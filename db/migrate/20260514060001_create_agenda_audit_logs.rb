class CreateAgendaAuditLogs < ActiveRecord::Migration[7.0]
  # PR #8 da auditoria 2026-05-13: AuditLog automático em entidades de agenda.
  #
  # Espelha a estrutura de `financial_audit_logs` (canon Klivy F-02):
  # - Polimórfico por (entity_type, entity_id) — escalável pra auditar
  #   AgendaService, AgendaEvent, AgendaCategory, etc. sem nova tabela.
  # - Sem `updated_at`: log é IMUTÁVEL por convenção (compliance LGPD/CFM).
  # - `before`/`after` em JSONB capturam o diff completo.
  # - Índices cobrem queries típicas: por entidade, por usuário, ordenado
  #   cronologicamente.
  #
  # Inserção é async via `Agenda::AuditLogJob` — não bloqueia a transação
  # principal do save da entidade auditada.

  def change
    create_table :agenda_audit_logs do |t|
      t.bigint :account_id, null: false
      t.bigint :user_id
      t.string :entity_type, limit: 80, null: false
      t.bigint :entity_id, null: false
      t.string :action, limit: 30, null: false
      t.string :ip_address, limit: 45
      t.string :user_agent
      t.jsonb :before, default: {}
      t.jsonb :after, default: {}
      t.jsonb :metadata, default: {}
      t.datetime :created_at, null: false

      t.index :account_id
      t.index [:account_id, :action], name: 'index_agenda_audit_logs_on_account_id_and_action'
      t.index [:account_id, :created_at], name: 'index_agenda_audit_logs_on_account_id_and_created'
      t.index [:account_id, :entity_type, :entity_id], name: 'idx_agenda_audit_logs_on_entity'
      t.index [:account_id, :user_id, :created_at], name: 'idx_agenda_audit_logs_chronological'
    end

    add_foreign_key :agenda_audit_logs, :accounts
  end
end
