class CreateAgendaNotificationLogs < ActiveRecord::Migration[7.1]
  def change
    create_table :agenda_notification_logs do |t|
      t.references :account,                    null: false, foreign_key: true
      t.references :agenda_event,               null: false, foreign_key: true
      t.references :agenda_notification_rule,   null: false, foreign_key: true

      t.datetime :sent_at,   null: false
      t.string   :status,    null: false, default: 'sent'
      # sent | failed | skipped

      t.text :error_message

      t.timestamps
    end

    # Índice único para evitar disparo duplo: mesma regra no mesmo evento
    add_index :agenda_notification_logs,
              [:agenda_event_id, :agenda_notification_rule_id],
              unique: true,
              name: 'idx_notif_log_unique_event_rule'

    add_index :agenda_notification_logs, [:account_id, :status]
    add_index :agenda_notification_logs, :sent_at
  end
end
