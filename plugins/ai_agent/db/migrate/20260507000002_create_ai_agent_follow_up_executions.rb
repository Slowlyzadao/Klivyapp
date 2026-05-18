class CreateAiAgentFollowUpExecutions < ActiveRecord::Migration[7.1]
  def change
    create_table :ai_agent_follow_up_executions do |t|
      t.references :account, null: false, foreign_key: true, index: true
      t.references :rule, null: false,
                          foreign_key: { to_table: :ai_agent_follow_up_rules, on_delete: :cascade },
                          index: true

      # Alvo do follow-up. Pode ser um agendamento (pre/post/no_show) ou
      # apenas um contato/conversa (no_response/custom).
      t.bigint :contact_id
      t.bigint :conversation_id
      t.bigint :agenda_event_id

      # Quando o disparo deveria acontecer (calculado pelo CandidateFinder).
      # Usado pra idempotência: dois jobs do mesmo dispatcher não podem
      # criar duas execuções pro mesmo (rule, target, target_at).
      t.datetime :target_at, null: false
      t.datetime :sent_at

      # pending → enfileirado pelo dispatcher; sent → posted; skipped →
      # caiu em opt-out, conversa fechada, etc; failed → erro irrecuperável.
      t.string :status, null: false, default: 'pending'
      t.string :skip_reason

      # FK pra Chatwoot Message quando posted. Não usamos foreign_key
      # constraint — Chatwoot core fica em outro plugin de namespace.
      t.bigint :message_id

      t.timestamps
    end

    # Idempotência forte: mesmo (rule + alvo + horário) só uma vez. Se o
    # cron rodar duplo ou o operador clicar dispatch duas vezes, segura
    # via banco (não via aplicação).
    add_index :ai_agent_follow_up_executions,
              %i[rule_id contact_id agenda_event_id target_at],
              unique: true,
              name: 'idx_ai_agent_follow_up_executions_unique_target'

    add_index :ai_agent_follow_up_executions, %i[account_id status target_at], name: 'idx_ai_agent_follow_up_executions_status'
  end
end
