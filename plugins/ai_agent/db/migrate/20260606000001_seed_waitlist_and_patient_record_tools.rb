class SeedWaitlistAndPatientRecordTools < ActiveRecord::Migration[7.1]
  TOOLS = [
    {
      key: 'add_to_waiting_list',
      name: 'Adicionar à lista de espera',
      description: 'Adiciona o paciente à lista de espera da clínica quando não há horário disponível, a disponibilidade é distante, ou o paciente recusa as opções. A clínica chama de volta ao abrir vaga.',
      requires_oauth: false,
      builtin: true
    },
    {
      key: 'update_patient_record',
      name: 'Atualizar ficha do paciente',
      description: 'Atualiza a ficha do paciente com CPF (pedido só ao confirmar o agendamento), origem (como conheceu a clínica) e dados do responsável (menor de idade).',
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
