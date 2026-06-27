# Fase 5 do motor de follow-up: tom/persona próprio por TIPO de follow-up
# (o "modo follow-up dedicado": no-show ≠ reativação ≠ pós-consulta).
#
# Texto livre anexado ao system prompt do MessageGenerator quando a regra
# é generativa — sobrepõe o tom padrão da Bea pra aquela campanha. Só
# afeta o modo `generative` (no estático a mensagem é fixa).
class AddPersonaOverrideToAiAgentFollowUpRules < ActiveRecord::Migration[7.1]
  def change
    add_column :ai_agent_follow_up_rules, :persona_override, :text
  end
end
