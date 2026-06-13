# Cooldown anti-spam configurável POR REGRA (antes era fixo em 2h, global e
# cego entre regras — derrubava lembretes legítimos). `cooldown_minutes` é o
# intervalo mínimo desde o último follow-up de OUTRA regra pro mesmo paciente;
# 0 = sem cooldown. Default 10 min (decisão do Leandro) — só barra rajada.
class AddCooldownMinutesToAiAgentFollowUpRules < ActiveRecord::Migration[7.1]
  def change
    add_column :ai_agent_follow_up_rules, :cooldown_minutes, :integer, null: false, default: 10
  end
end
