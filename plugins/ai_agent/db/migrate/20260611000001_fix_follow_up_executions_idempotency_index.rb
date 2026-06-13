# Auditoria 2026-06-11: o índice único de idempotência
# `(rule_id, contact_id, agenda_event_id, target_at)` tinha DOIS furos:
#   1. NULLs são distintos em UNIQUE no Postgres — então triggers sem
#      agendamento (no_response, service_recall) têm agenda_event_id NULL
#      e o índice NÃO impedia execuções duplicadas em corridas do cron.
#   2. Não incluía step_id — dois passos da cadência com o mesmo offset
#      geravam o mesmo target_at e colidiam, perdendo um beat em silêncio.
#
# Correção: índice funcional com COALESCE(agenda_event_id, 0) e
# COALESCE(step_id, 0), tratando NULL como 0 (nenhum id real é 0). Assim a
# idempotência forte do banco passa a cobrir TODOS os triggers e cada passo.
class FixFollowUpExecutionsIdempotencyIndex < ActiveRecord::Migration[7.1]
  OLD = 'idx_ai_agent_follow_up_executions_unique_target'.freeze
  NEW = 'idx_ai_agent_fue_unique_target_v2'.freeze

  def up
    remove_index :ai_agent_follow_up_executions, name: OLD, if_exists: true
    execute <<~SQL.squish
      CREATE UNIQUE INDEX #{NEW}
      ON ai_agent_follow_up_executions
      (rule_id, contact_id, COALESCE(agenda_event_id, 0), COALESCE(step_id, 0), target_at)
    SQL
  end

  def down
    execute "DROP INDEX IF EXISTS #{NEW}"
    add_index :ai_agent_follow_up_executions,
              %i[rule_id contact_id agenda_event_id target_at],
              unique: true, name: OLD
  end
end
