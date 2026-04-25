class CreateAgendaOnlineConfigs < ActiveRecord::Migration[7.1]
  def change
    create_table :agenda_online_configs do |t|
      t.references :account, null: false, foreign_key: true
      t.boolean :enabled, default: true
      t.boolean :allow_new_patients, default: true
      t.boolean :require_whatsapp_verification, default: false
      t.boolean :require_email_verification, default: false
      t.integer :min_lead_time_minutes, default: 180
      t.integer :future_limit_days, default: 60
      t.jsonb :form_fields, default: []

      t.timestamps
    end
  end
end
