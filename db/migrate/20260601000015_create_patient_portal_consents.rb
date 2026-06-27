# Termo do portal aceito pelo paciente. Separado de `ConsentRecord` (do plugin
# Pacientes, que cobre termos clínicos por procedimento). Aqui guardamos só os
# termos Klivy: `portal_terms` (Termo de Uso) e `lgpd` (Política de Privacidade).
class CreatePatientPortalConsents < ActiveRecord::Migration[7.1]
  def change
    create_table :patient_portal_consents do |t|
      t.references :account, null: false, foreign_key: true
      t.references :patient, null: false, foreign_key: true

      t.string :term_type, null: false       # 'portal_terms' | 'lgpd'
      t.string :term_version, null: false    # ex: '1.0'

      t.datetime :accepted_at, null: false
      t.datetime :revoked_at
      t.text :revocation_reason

      t.string :ip
      t.string :user_agent

      t.timestamps

      t.index [:patient_id, :term_type, :term_version], unique: true,
              name: 'idx_pp_consents_patient_term_version'
    end
  end
end
