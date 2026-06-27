# Reativação por serviço só aceitava MESES — clínicas com procedimentos de
# ciclo curto (limpeza de pele quinzenal, retorno em 15 dias) não conseguiam
# configurar. Espelha o padrão offset_hours/offset_unit das outras regras:
# o valor numérico + uma unidade (days/weeks/months, default months — os
# registros existentes continuam significando exatamente o mesmo).
class AddRecallIntervalUnitToAiAgentFollowUpRules < ActiveRecord::Migration[7.1]
  def change
    rename_column :ai_agent_follow_up_rules, :recall_interval_months, :recall_interval_value
    add_column :ai_agent_follow_up_rules, :recall_interval_unit, :string, null: false, default: 'months'
  end
end
