# Sessões JWT do portal. PRD §5.2: JWT vale 7 dias (30 dias se "lembrar
# dispositivo"). `jti` (JWT ID) é único — permite revogar uma sessão específica.
class CreatePatientPortalSessions < ActiveRecord::Migration[7.1]
  def change
    create_table :patient_portal_sessions do |t|
      t.references :account, null: false, foreign_key: true
      t.references :patient, null: false, foreign_key: true

      t.string :jwt_jti, null: false             # JWT ID, único
      t.datetime :expires_at, null: false
      t.datetime :last_seen_at
      t.datetime :revoked_at

      t.string :ip
      t.string :user_agent
      t.string :device_fingerprint               # opt-in "lembrar dispositivo"

      t.timestamps

      t.index :jwt_jti, unique: true
      t.index [:patient_id, :expires_at]
    end
  end
end
