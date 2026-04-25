class CreatePatientAppointments < ActiveRecord::Migration[7.1]
  def change
    create_table :patient_appointments do |t|
      # Relações principais
      t.references :account,     null: false, foreign_key: true
      t.references :patient,     null: false, foreign_key: true
      t.references :professional, null: true, foreign_key: { to_table: :users }
      t.references :agenda_event, null: true, foreign_key: true  # Liga ao AgendaEvent existente

      # Dados do agendamento
      t.string  :appointment_type,    null: false, default: 'avaliacao'
      t.string  :status,              null: false, default: 'scheduled'
      t.datetime :scheduled_at,       null: false
      t.datetime :ends_at,            null: true
      t.integer  :duration_minutes,   default: 60
      t.string  :cancellation_reason, null: true
      t.string  :reschedule_reason,   null: true
      t.text    :notes,               null: true

      # Recall / Retorno
      t.boolean :recall_sent,         default: false, null: false
      t.datetime :recall_sent_at,     null: true
      t.integer  :return_in_days,     null: true  # Se preenchido, sugere retorno em N dias

      # Links para recursos do prontuário
      t.bigint  :session_log_id,      null: true  # Sessão vinculada quando realizado
      t.bigint  :treatment_plan_id,   null: true  # Plano de tratamento relacionado

      # Soft delete
      t.datetime :deleted_at,         null: true

      t.timestamps null: false
    end

    add_index :patient_appointments, :status
    add_index :patient_appointments, :appointment_type
    add_index :patient_appointments, :scheduled_at
    add_index :patient_appointments, :deleted_at
    add_index :patient_appointments, [:patient_id, :status]
    add_index :patient_appointments, [:patient_id, :scheduled_at]
  end
end
