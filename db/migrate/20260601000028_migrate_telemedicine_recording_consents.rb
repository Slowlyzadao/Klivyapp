# Copia rows de patient_portal_consents (term_type='telemedicine_recording')
# para telemed_consents. SQL puro pra ser data-pipeline-safe (sem callbacks).
#
# Idempotente via INSERT ... ON CONFLICT DO NOTHING. Rodar 2× = no-op.
class MigrateTelemedicineRecordingConsents < ActiveRecord::Migration[7.1]
  def up
    execute <<~SQL
      INSERT INTO telemed_consents
        (account_id, patient_id, term_version, accepted_at, ip, user_agent, revoked_at, created_at, updated_at)
      SELECT
        account_id, patient_id, term_version, accepted_at, ip, user_agent, revoked_at, created_at, updated_at
      FROM patient_portal_consents
      WHERE term_type = 'telemedicine_recording'
      ON CONFLICT (account_id, patient_id, term_version) DO NOTHING;
    SQL

    # Não deletamos as rows antigas — mantemos como audit trail histórico
    # até a próxima cleanup window. Quando confirmado que o novo fluxo está
    # em produção (e o split funciona), uma migration futura pode rodar:
    #   DELETE FROM patient_portal_consents WHERE term_type='telemedicine_recording';
  end

  def down
    # Down não recupera as rows antigas (continuam em patient_portal_consents).
    execute "DELETE FROM telemed_consents;"
  end
end
