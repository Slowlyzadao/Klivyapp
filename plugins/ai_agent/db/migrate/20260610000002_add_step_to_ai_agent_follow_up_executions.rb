# Rastreia QUAL passo da cadência gerou cada execução. Nullable: o
# passo 1 (a própria regra) não tem row em follow_up_steps, então
# `step_id` fica nil e o SendFollowUpJob cai no `context_brief` da regra.
#
# NÃO entra no índice único de idempotência — o `target_at` já é distinto
# por passo (offsets diferentes), então o UNIQUE atual
# (rule_id, contact_id, agenda_event_id, target_at) já separa os passos.
# Sem FK constraint (mesmo padrão de `message_id`): se um passo for
# removido, a execução histórica permanece com o id órfão pra auditoria.
class AddStepToAiAgentFollowUpExecutions < ActiveRecord::Migration[7.1]
  def change
    add_column :ai_agent_follow_up_executions, :step_id, :bigint
    add_index :ai_agent_follow_up_executions, :step_id,
              name: 'idx_ai_agent_follow_up_executions_step'
  end
end
