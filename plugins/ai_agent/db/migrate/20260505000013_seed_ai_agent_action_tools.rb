class SeedAiAgentActionTools < ActiveRecord::Migration[7.1]
  ACTION_TOOLS = [
    {
      key: 'patient_lookup',
      name: 'Buscar paciente atual',
      description: 'Resolve o prontuário do paciente da conversa atual (nome, status, alergias, profissional responsável).',
      requires_oauth: false,
      builtin: true
    },
    {
      key: 'list_appointments',
      name: 'Listar consultas do paciente',
      description: 'Lista próximas consultas do paciente atual no plugin Agenda. Apenas leitura.',
      requires_oauth: false,
      builtin: true
    },
    {
      key: 'financial_status',
      name: 'Situação financeira do paciente',
      description: 'Mostra parcelas pendentes/em atraso do paciente. Apenas leitura — sem negociar.',
      requires_oauth: false,
      builtin: true
    },
    {
      key: 'notify_staff',
      name: 'Notificar equipe',
      description: 'Cria nota interna privada na conversa avisando a recepção sobre algo relevante.',
      requires_oauth: false,
      builtin: true
    }
  ].freeze

  def up
    ACTION_TOOLS.each do |attrs|
      next if AiAgent::ToolDefinition.where(key: attrs[:key]).exists?

      AiAgent::ToolDefinition.create!(attrs.merge(enabled_globally: true))
    end
  end

  def down
    ACTION_TOOLS.each do |attrs|
      AiAgent::ToolDefinition.where(key: attrs[:key]).delete_all
    end
  end
end
