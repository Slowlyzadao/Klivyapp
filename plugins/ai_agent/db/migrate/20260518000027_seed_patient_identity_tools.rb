class SeedPatientIdentityTools < ActiveRecord::Migration[7.1]
  TOOLS = [
    {
      key: 'find_patient_by_phone',
      name: 'Buscar paciente por telefone',
      description: 'Procura pacientes da clínica que tenham o mesmo telefone do Contact ativo na conversa. Use antes de pedir nome ou criar novo cadastro.',
      requires_oauth: false,
      builtin: true
    },
    {
      key: 'confirm_patient_identity',
      name: 'Confirmar identidade do paciente',
      description: 'Confirma que o paciente é a pessoa retornada por find_patient_by_phone e vincula a ficha ao Contact desta conversa (auto-link retroativo).',
      requires_oauth: false,
      builtin: true
    },
    {
      key: 'create_patient_minimal',
      name: 'Criar ficha mínima do paciente',
      description: 'Cria ficha nova com nome completo + telefone do WhatsApp + contact_id quando find_patient_by_phone retornou vazio. Não pede CPF/nascimento.',
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
