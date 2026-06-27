class AddResponsiblePhysicianAndSeedErasure < ActiveRecord::Migration[7.1]
  ERASURE_TOOL = {
    key: 'erasure_request',
    name: 'Pedido de exclusão de dados (LGPD)',
    description: 'Registra pedido formal do paciente para exclusão dos dados pessoais (LGPD art. 18 VI). Não apaga nada automaticamente — abre ticket interno via notify_staff e direciona o paciente para o canal oficial. Decisão D-23.',
    requires_oauth: false,
    builtin: true
  }.freeze

  def up
    # Médico responsável técnico pela clínica (CFM 2.454/2026 — exige
    # médico identificável em qualquer clínica que atende presencialmente
    # ou remotamente). Para clínicas odontológicas o conselho costuma
    # ser CRO; para psicologia, CRP; daí o `council` ser configurável
    # em vez de fixo "CRM".
    add_reference :ai_agent_account_settings, :responsible_physician,
                  null: true,
                  foreign_key: { to_table: :users },
                  index: true
    add_column :ai_agent_account_settings, :responsible_physician_crm, :string
    add_column :ai_agent_account_settings, :responsible_physician_council, :string

    # Seed do erasure_request_tool (idempotente).
    return if AiAgent::ToolDefinition.where(key: ERASURE_TOOL[:key]).exists?

    AiAgent::ToolDefinition.create!(ERASURE_TOOL.merge(enabled_globally: true))
  end

  def down
    AiAgent::ToolDefinition.where(key: ERASURE_TOOL[:key]).delete_all
    remove_column :ai_agent_account_settings, :responsible_physician_council
    remove_column :ai_agent_account_settings, :responsible_physician_crm
    remove_reference :ai_agent_account_settings, :responsible_physician,
                     foreign_key: { to_table: :users }
  end
end
