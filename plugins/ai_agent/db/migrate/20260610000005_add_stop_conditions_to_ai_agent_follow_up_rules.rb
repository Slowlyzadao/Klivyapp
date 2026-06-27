# Fase 3 do motor de follow-up: condições de saída da cadência.
#   stop_on_reply   → não dispara os próximos passos se o paciente respondeu
#                     (mandou mensagem) depois do nosso último envio dessa regra.
#   stop_on_booking → não dispara se o paciente tem agendamento futuro
#                     (scheduled/confirmed) — útil em no_response/reativação,
#                     onde o objetivo é justamente fazer o paciente marcar.
#
# Default false (opt-in no banco; o passo 1 nunca é afetado por stop_on_reply,
# pois não há envio anterior). A UI liga ambos por padrão em regras novas.
class AddStopConditionsToAiAgentFollowUpRules < ActiveRecord::Migration[7.1]
  def change
    add_column :ai_agent_follow_up_rules, :stop_on_reply, :boolean, null: false, default: false
    add_column :ai_agent_follow_up_rules, :stop_on_booking, :boolean, null: false, default: false
  end
end
