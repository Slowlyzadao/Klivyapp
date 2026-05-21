# Subscriptions de Web Push do paciente (PRD §17, Sprint G).
#
# Cada device/browser que aceita push gera um endpoint único — guardamos para
# disparar notificações via VAPID. Um paciente pode ter N subscriptions
# (smartphone Android + iPhone + desktop, por exemplo).
#
# `endpoint` é único globalmente (vem do FCM/Mozilla/Apple push service).
class CreatePatientPortalPushSubscriptions < ActiveRecord::Migration[7.1]
  def change
    create_table :patient_portal_push_subscriptions do |t|
      t.references :account,  null: false, foreign_key: true, index: true
      t.references :patient,  null: false, foreign_key: true, index: true

      t.string :endpoint,     null: false, limit: 1024
      t.string :p256dh_key,   null: false
      t.string :auth_key,     null: false

      t.string :user_agent,   limit: 500
      t.datetime :last_used_at
      t.integer :failure_count, null: false, default: 0
      t.datetime :disabled_at

      t.timestamps
    end

    add_index :patient_portal_push_subscriptions, :endpoint, unique: true,
              name: 'idx_pp_push_subs_endpoint_unique'
  end
end
