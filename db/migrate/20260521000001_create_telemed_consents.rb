# Cria tabela telemed_consents como parte da extração do plugin telemed.
# Antes, consents de gravação ficavam em patient_portal_consents com
# term_type='telemedicine_recording'. Separação isola dados do plugin.
#
# A migration de dados (20260521000002) copia rows existentes; esta
# apenas cria a estrutura.
class CreateTelemedConsents < ActiveRecord::Migration[7.1]
  def change
    create_table :telemed_consents do |t|
      t.references :account, null: false, foreign_key: true, index: true
      t.references :patient, null: false, foreign_key: true, index: true
      t.string     :term_version, null: false, default: '1.0'
      t.datetime   :accepted_at,  null: false
      t.string     :ip,           limit: 64
      t.string     :user_agent,   limit: 255
      t.datetime   :revoked_at
      t.timestamps
    end

    # Único consent ativo por (account, patient) — caso a clínica re-emita
    # versão do termo, é só criar nova row com term_version diferente.
    add_index :telemed_consents,
              [:account_id, :patient_id, :term_version],
              unique: true,
              name: 'idx_telemed_consents_unique_per_version'
  end
end
