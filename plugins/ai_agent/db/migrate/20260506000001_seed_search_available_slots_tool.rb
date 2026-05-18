class SeedSearchAvailableSlotsTool < ActiveRecord::Migration[7.1]
  TOOL = {
    key: 'search_available_slots',
    name: 'Buscar horários disponíveis',
    description: 'Retorna até 5 horários reais bookáveis na agenda, respeitando horário de funcionamento, almoço e eventos já marcados. Apenas leitura.',
    requires_oauth: false,
    builtin: true
  }.freeze

  def up
    return if AiAgent::ToolDefinition.where(key: TOOL[:key]).exists?

    AiAgent::ToolDefinition.create!(TOOL.merge(enabled_globally: true))
  end

  def down
    AiAgent::ToolDefinition.where(key: TOOL[:key]).delete_all
  end
end
