class AddAppliesToToAiAgentFollowUpRules < ActiveRecord::Migration[7.1]
  def change
    # Filtro por origem do AgendaEvent. 'both' (default) preserva
    # comportamento atual — regra dispara pra qualquer agendamento.
    # 'ai_agent' = só agendamentos criados pela Bea via book_appointment_tool.
    # 'manual'   = só os criados por humano (recepção via UI/REST) ou
    #              importação. Não distingue 'public_booking' separadamente
    #              porque isso é um caso de uso diferente; quem precisar
    #              filtrar booking público pode usar 'manual' ou estender
    #              esse enum no futuro.
    add_column :ai_agent_follow_up_rules, :applies_to, :string, null: false, default: 'both'
  end
end
