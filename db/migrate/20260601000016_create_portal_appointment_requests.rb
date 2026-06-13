# Solicitações de agendamento criadas pelo paciente via portal (PRD §7).
#
# É a "fila de pedidos" que a recepção processa — uma vez aprovada, vira um
# `AgendaEvent` real (FK preenchido em `agenda_event_id`). Não tocamos
# `AgendaEvent` diretamente porque queremos:
#   1. Auditar a intenção do paciente antes da clínica aceitar.
#   2. Permitir múltiplas sugestões de horário sem poluir a agenda.
#   3. Preservar o histórico de rejeição com motivo.
class CreatePortalAppointmentRequests < ActiveRecord::Migration[7.1]
  def change
    create_table :portal_appointment_requests do |t|
      t.references :account, null: false, foreign_key: true
      t.references :patient, null: false, foreign_key: true

      # Preferências do paciente — todas opcionais. A clínica decide o slot final.
      t.bigint   :preferred_professional_id
      t.bigint   :preferred_service_id
      t.jsonb    :preferred_dates, default: []    # array de ISO strings (1..3 sugestões)
      t.string   :preferred_period                # 'morning' | 'afternoon' | 'evening'
      t.text     :notes

      # Estado do pedido
      t.string   :status, null: false, default: 'pending'
      # 'pending' | 'approved' | 'rejected' | 'scheduled' | 'cancelled'

      t.bigint   :processed_by_id
      t.datetime :processed_at
      t.text     :processed_notes

      # Quando aprovado e marcado, aponta para o agendamento criado.
      t.bigint   :agenda_event_id

      t.timestamps

      t.index :status
      t.index [:patient_id, :status]
    end
  end
end
