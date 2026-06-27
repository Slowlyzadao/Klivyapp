class SeedAiAgentBuiltinTools < ActiveRecord::Migration[7.1]
  BUILTIN_TOOLS = [
    {
      key: 'search_knowledge',
      name: 'Buscar conhecimento',
      description: 'Consulta a base de conhecimento da clínica (RAG) para responder perguntas sobre políticas, horários, serviços, valores e convênios.',
      requires_oauth: false,
      builtin: true
    },
    {
      key: 'transfer_to_human',
      name: 'Transferir para humano',
      description: 'Escala a conversa para um atendente humano quando o paciente pede explicitamente, demonstra frustração persistente, ou toca em tema sensível.',
      requires_oauth: false,
      builtin: true
    }
  ].freeze

  def up
    BUILTIN_TOOLS.each do |attrs|
      next if AiAgent::ToolDefinition.where(key: attrs[:key]).exists?

      AiAgent::ToolDefinition.create!(attrs.merge(enabled_globally: true))
    end
  end

  def down
    AiAgent::ToolDefinition.where(builtin: true).delete_all
  end
end
