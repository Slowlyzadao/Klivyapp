class CreateFinancialLgpdRequestsAndPatientAnonymization < ActiveRecord::Migration[7.1]
  # F-33 §parte 2 — workflow LGPD de anonimização de paciente.
  #
  # Tabela `financial_lgpd_requests`:
  #   - paciente solicita exclusão (status='pending')
  #   - ADMIN aprova (status='approved')
  #   - sistema executa anonimização (status='executed', patient.anonymized_at = now)
  #   - OU rejeita (status='rejected', com motivo)
  #
  # Coluna `patients.anonymized_at` marca pacientes anonimizados —
  # serializers escondem dados pessoais quando presente.
  def change
    create_table :financial_lgpd_requests do |t|
      t.bigint :account_id, null: false
      t.bigint :patient_id, null: false

      # pending | approved | executed | rejected | cancelled
      t.string :status, limit: 20, null: false, default: 'pending'

      # Motivo informado pelo paciente (opcional — alguns pedem só genérico)
      t.text :reason

      t.datetime :requested_at, null: false

      t.datetime :approved_at
      t.bigint   :approved_by_id

      t.datetime :executed_at
      t.bigint   :executed_by_id

      t.datetime :rejected_at
      t.bigint   :rejected_by_id
      t.text     :rejection_reason

      # Snapshot pra auditoria — depois da execução não dá pra recuperar
      # quais campos estavam preenchidos.
      t.jsonb :anonymized_fields, default: {}

      t.text :notes
      t.datetime :deleted_at
      t.bigint :deleted_by_id
      t.bigint :created_by_id
      t.bigint :updated_by_id

      t.timestamps null: false
    end

    add_index :financial_lgpd_requests, :account_id
    add_index :financial_lgpd_requests, :patient_id
    add_index :financial_lgpd_requests, :status
    add_index :financial_lgpd_requests, :deleted_at

    # Coluna em patients pra marcar quem foi anonimizado.
    add_column :patients, :anonymized_at, :datetime
    add_index  :patients, :anonymized_at
  end
end
