# Fase 6 do motor de follow-up: reativação por SERVIÇO (ex: botox a cada
# 6 meses). O card aponta pra um serviço e define o intervalo — tudo na
# própria regra, sem tocar no plugin agenda (o serviço é lido por id).
#
#   agenda_service_id     → qual serviço dispara a reativação (lido do
#                           plugin agenda, sem FK p/ manter independência).
#   recall_interval_months → de quanto em quanto tempo reativar (ex: 6).
#
# Usados só pelo trigger `service_recall`; nos demais ficam nil.
class AddServiceRecallToAiAgentFollowUpRules < ActiveRecord::Migration[7.1]
  def change
    add_column :ai_agent_follow_up_rules, :agenda_service_id, :bigint
    add_column :ai_agent_follow_up_rules, :recall_interval_months, :integer

    add_index :ai_agent_follow_up_rules, :agenda_service_id,
              name: 'idx_ai_agent_follow_up_rules_service'
  end
end
