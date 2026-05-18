class SeedClinicAndBookingTools < ActiveRecord::Migration[7.1]
  TOOLS = [
    {
      key: 'clinic_info',
      name: 'Informações da clínica',
      description: 'Horário de funcionamento, feriados, lista de serviços com duração e preço, regras gerais. Apenas leitura.',
      requires_oauth: false,
      builtin: true
    },
    {
      key: 'book_appointment',
      name: 'Agendar consulta',
      description: 'Cria um AgendaEvent para o paciente atual com status scheduled. Recepção confirma depois.',
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
