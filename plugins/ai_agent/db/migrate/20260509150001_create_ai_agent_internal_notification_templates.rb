class CreateAiAgentInternalNotificationTemplates < ActiveRecord::Migration[7.1]
  # Templates de notificação interna que a Bea posta no Chat Interno quando
  # gatilhos de domínio acontecem (ex: agendamento pendente confirmação,
  # paciente ofensivo, emergência clínica). Cada conta tem 1 template ativo
  # por event_key (UNIQUE), editável via /captain/<id>/templates.
  #
  # target_type: 'room' (sala do chat) | 'user' (DM idempotente) | 'disabled'
  # target_id: room_id ou user_id (NULL se disabled)
  #
  # body é um template estilo `format(body, vars)` — variáveis em %{nome}.
  # Vars permitidas por event_key vivem em AiAgent::InternalNotifier::EventCatalog.
  def change
    create_table :ai_agent_internal_notification_templates do |t|
      t.references :account, null: false, foreign_key: true
      t.string  :event_key,   null: false
      t.string  :name,        null: false
      t.text    :body,        null: false
      t.string  :target_type, null: false, default: 'room'
      t.bigint  :target_id
      t.boolean :enabled,     null: false, default: true
      t.timestamps
    end

    add_index :ai_agent_internal_notification_templates,
              [:account_id, :event_key],
              unique: true,
              name: 'idx_ai_internal_notif_tpl_account_event'
  end
end
