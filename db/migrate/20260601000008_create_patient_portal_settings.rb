# Configuração do Portal do Paciente por account.
# Estrutura jsonb por categoria conforme PRD §14.7 — cada chave é um campo
# dentro do jsonb da categoria (catálogo completo em patient-portal-fluxos.md §2).
#
# MVP popula só o subconjunto necessário pra preset "Autonomia Guiada"
# (PRD §4.5). Demais campos têm default zero/nulo até serem usados em F2/F3.
class CreatePatientPortalSettings < ActiveRecord::Migration[7.1]
  def change
    create_table :patient_portal_settings do |t|
      t.references :account, null: false, foreign_key: true, index: { unique: true }

      # Preset escolhido pela clínica (PRD §4.5)
      t.string :active_preset, null: false, default: 'autonomy_guided'

      # Categorias de configuração — jsonb permite evoluir o catálogo sem migration nova.
      t.jsonb :scheduling,                null: false, default: {}
      t.jsonb :rescheduling,              null: false, default: {}
      t.jsonb :financial,                 null: false, default: {}
      t.jsonb :documents,                 null: false, default: {}
      t.jsonb :clinical,                  null: false, default: {}
      t.jsonb :messaging,                 null: false, default: {}
      t.jsonb :engagement,                null: false, default: {}
      t.jsonb :invite,                    null: false, default: {}
      t.jsonb :business_hours,            null: false, default: {}
      t.jsonb :notification_events_enabled, null: false, default: {}

      # FK opcional para inboxes auto-criados (PRD §16.5)
      t.bigint :default_inbox_id
      t.bigint :appointment_request_inbox_id
      t.bigint :document_request_inbox_id
      t.bigint :compliance_inbox_id
      t.bigint :urgent_inbox_id

      t.timestamps
    end
  end
end
