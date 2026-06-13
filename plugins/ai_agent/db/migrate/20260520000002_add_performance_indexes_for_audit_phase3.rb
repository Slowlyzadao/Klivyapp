# PERF-6, PERF-7, PERF-8 (auditoria 2026-05-18). Três índices motivados por
# queries hot-path identificadas na Fase 3 de performance:
#
#   - PERF-6: cooldown query do FollowUpDispatcherJob (roda cada 1 minuto).
#   - PERF-7: health checker global do Bea (roda cada 10 minutos).
#   - PERF-8: eligibility query do ConsolidatePatientMemoryJob (cron diário).
#
# Todos os índices criados CONCURRENTLY pra não bloquear escritas em prod
# durante o build. Migration sem ddl_transaction (CONCURRENTLY exige).
class AddPerformanceIndexesForAuditPhase3 < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    # PERF-6: cooldown anti-spam no dispatcher de follow-ups. Query é
    # `WHERE account_id = ? AND contact_id = ? AND status = 'sent' AND sent_at >= ?`
    # — checada por candidato a cada minuto. Sem este índice composto, scan
    # cai no índice existente `(account_id, status, target_at)` (sem
    # contact_id na chave), exigindo filter in-memory por contact.
    add_index :ai_agent_follow_up_executions,
              %i[account_id contact_id status sent_at],
              name: 'idx_follow_up_exec_cooldown',
              algorithm: :concurrently,
              if_not_exists: true

    # PERF-7: health checker faz `Trace.where(created_at: 24.hours.ago..)`
    # SEM filtro por account_id (agregação global de saúde da plataforma).
    # O índice existente `(account_id, created_at)` exige leftmost prefix
    # e não é usado nessa query global. Postgres acaba em seq scan.
    # Índice simples em `created_at` cobre 100% da janela de 24h sem
    # depender de account_id.
    add_index :ai_agent_traces,
              :created_at,
              name: 'idx_ai_agent_traces_created_at',
              algorithm: :concurrently,
              if_not_exists: true

    # PERF-8: eligibility do ConsolidatePatientMemoryJob faz
    # `WHERE jsonb_array_length(history) >= 5` — sem expression index isso
    # é full table scan diário. Index funcional em
    # `jsonb_array_length(history)` resolve em index range scan.
    # `using: :btree` é o default; explícito por clareza dado que é
    # expression index (Postgres aceita btree em qualquer expressão imutável).
    add_index :ai_agent_patient_memories,
              'jsonb_array_length(history)',
              name: 'idx_patient_memory_history_len',
              using: :btree,
              algorithm: :concurrently,
              if_not_exists: true
  end

  def down
    remove_index :ai_agent_follow_up_executions,
                 name: 'idx_follow_up_exec_cooldown',
                 algorithm: :concurrently,
                 if_exists: true
    remove_index :ai_agent_traces,
                 name: 'idx_ai_agent_traces_created_at',
                 algorithm: :concurrently,
                 if_exists: true
    remove_index :ai_agent_patient_memories,
                 name: 'idx_patient_memory_history_len',
                 algorithm: :concurrently,
                 if_exists: true
  end
end
