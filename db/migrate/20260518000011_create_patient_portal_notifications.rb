# Notificações in-app do portal do paciente (PRD §13ter).
#
# Push real (web push / FCM) entra em outra fase — esse modelo cobre o caso
# in-app que é o gancho de UX mais imediato (badge no sino + lista navegável).
# Outros sistemas (Sprint C/D já passaram) só precisam chamar
# `PatientPortal::NotificationDispatcher.dispatch(...)` quando algo de relevante
# acontecer (agendamento confirmado, consent vencendo, charge nova, etc.).
class CreatePatientPortalNotifications < ActiveRecord::Migration[7.1]
  def change
    create_table :patient_portal_notifications do |t|
      t.references :account, null: false, foreign_key: true
      t.references :patient, null: false, foreign_key: true

      # Tipo da notificação — usado pelo front pra escolher ícone/cor/CTA.
      # 'appointment_confirmed', 'appointment_canceled', 'document_ready',
      # 'consent_pending', 'consent_signed', 'recall', 'message_received',
      # 'financial_charge', 'generic'
      t.string   :kind, null: false

      t.string   :title, null: false
      t.text     :body
      t.jsonb    :payload, default: {}  # link interno, IDs relacionados, etc.

      t.datetime :read_at  # nil = não lida

      t.timestamps

      t.index [:patient_id, :read_at]
      t.index [:account_id, :patient_id, :created_at], name: 'idx_pp_notifications_recent'
    end
  end
end
