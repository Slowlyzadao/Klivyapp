# Códigos OTP para login passwordless do paciente. PRD §5.4:
# - TTL 10 min, máximo 3 tentativas, invalidado após uso.
# - Identifier é phone E.164 normalizado OU email normalizado (downcase).
# - code_digest guarda Argon2/bcrypt do código — nunca o código em claro.
class CreatePatientPortalOtps < ActiveRecord::Migration[7.1]
  def change
    create_table :patient_portal_otps do |t|
      t.string :identifier, null: false           # phone (+5511...) ou email
      t.string :code_digest, null: false          # bcrypt(code)
      t.string :channel, null: false              # 'whatsapp' | 'email'

      t.datetime :expires_at, null: false
      t.datetime :used_at
      t.integer :attempts, null: false, default: 0

      # IP de origem para auditoria + anti-flood
      t.string :ip

      t.timestamps

      t.index :identifier
      t.index :expires_at
    end
  end
end
