# Fase 2: texto fixo de cada passo adicional da cadência, usado quando a
# regra está no modo `static`. No modo `generative`, segue valendo o
# `context_brief` (instrução pra Bea). A validação de qual é obrigatório
# é condicional no model, conforme `rule.action_type`.
#
# `context_brief` deixa de ser NOT NULL pelo mesmo motivo da regra: um
# passo de regra estática não precisa de cenário pra Bea.
class AddStaticBodyToAiAgentFollowUpSteps < ActiveRecord::Migration[7.1]
  def change
    add_column :ai_agent_follow_up_steps, :static_body, :text

    change_column_null :ai_agent_follow_up_steps, :context_brief, true
  end
end
