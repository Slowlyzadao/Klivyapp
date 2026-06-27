# Fase 2 do motor de follow-up: modo de ação da regra.
#   generative → a Bea escreve a mensagem (comportamento atual, usa context_brief)
#   static     → mensagem fixa com variáveis ({{nome}}, {{data}}, ...), sem LLM
#
# `static_body` guarda o texto fixo do passo 1 (a própria regra). Os passos
# adicionais têm o seu em `ai_agent_follow_up_steps.static_body`.
#
# `context_brief` deixa de ser NOT NULL: numa regra `static`, o cenário pra
# Bea não é obrigatório (a validação de presença passa a ser condicional no
# model — exige context_brief no modo generativo, static_body no estático).
class AddActionTypeToAiAgentFollowUpRules < ActiveRecord::Migration[7.1]
  def change
    add_column :ai_agent_follow_up_rules, :action_type, :string, null: false, default: 'generative'
    add_column :ai_agent_follow_up_rules, :static_body, :text

    change_column_null :ai_agent_follow_up_rules, :context_brief, true
  end
end
