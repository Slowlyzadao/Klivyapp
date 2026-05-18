class SeedRescheduleAndCancelTools < ActiveRecord::Migration[7.1]
  TOOLS = [
    {
      key: 'reschedule_appointment',
      name: 'Remarcar consulta',
      description: 'Remarca uma consulta existente do paciente para nova data/hora. Mantém duração, profissional e serviço.',
      requires_oauth: false,
      builtin: true
    },
    {
      key: 'cancel_appointment',
      name: 'Cancelar consulta',
      description: 'Cancela (soft-cancel) uma consulta agendada do paciente. Slot fica livre, registro permanece com status=cancelled.',
      requires_oauth: false,
      builtin: true
    }
  ].freeze

  def up
    TOOLS.each do |attrs|
      next if AiAgent::ToolDefinition.where(key: attrs[:key]).exists?

      AiAgent::ToolDefinition.create!(attrs.merge(enabled_globally: true))
    end
  end

  def down
    TOOLS.each { |a| AiAgent::ToolDefinition.where(key: a[:key]).delete_all }
  end
end
