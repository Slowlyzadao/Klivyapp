class CreatePatientTimelineEvents < ActiveRecord::Migration[7.1]
  def change
    create_table :patient_timeline_events do |t|
      # Relações principais
      t.references :account,   null: false, foreign_key: true
      t.references :patient,   null: false, foreign_key: true
      t.references :actor,     null: true,  foreign_key: { to_table: :users }

      # Tipo e descrição do evento
      t.string  :event_type,    null: false  # ex: 'appointment_scheduled', 'payment', etc.
      t.text    :label,         null: false  # Descrição legível pelo humano
      t.string  :actor_name,    null: true   # Snapshot do nome (evita JOIN)

      # Referência polimórfica ao recurso que gerou o evento
      t.string  :reference_type, null: true  # 'Appointment', 'Transaction', etc.
      t.bigint  :reference_id,   null: true

      # Metadados extras para exibição no front
      t.jsonb   :metadata,       default: {}, null: false

      # Marcação temporal real do evento (pode diferir do created_at)
      t.datetime :occurred_at, null: false

      t.timestamps null: false
    end

    add_index :patient_timeline_events, :event_type
    add_index :patient_timeline_events, :occurred_at
    add_index :patient_timeline_events, [:patient_id, :occurred_at]
    add_index :patient_timeline_events, [:reference_type, :reference_id]
  end
end
