class AddOffsetUnitToAiAgentFollowUpRules < ActiveRecord::Migration[7.1]
  def change
    # `offset_hours` continua sendo o número informado pelo usuário, mas
    # agora a unidade é parametrizada. Valores existentes (todos em horas)
    # ficam intactos com unit='hours'. CandidateFinder usa `offset_seconds`
    # (calculado no model) pra disparar — não precisa migrar dados.
    add_column :ai_agent_follow_up_rules, :offset_unit, :string, null: false, default: 'hours'
  end
end
