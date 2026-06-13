# Convite emitido pela clínica para liberar acesso do paciente ao portal.
# PRD §5.6 cobre os 4 fluxos (auto / manual / via booking público / sem convite).
class CreatePortalInvites < ActiveRecord::Migration[7.1]
  def change
    create_table :portal_invites do |t|
      t.references :account, null: false, foreign_key: true
      t.references :patient, null: false, foreign_key: true
      t.bigint :invited_by_user_id # null quando convite automático (auto_invite_on_create)

      # Canal do envio — `whatsapp` exige inbox configurado; `email` usa ActionMailer.
      t.string :channel, null: false, default: 'whatsapp'

      # Token único do convite (paciente clica e cai no fluxo de OTP)
      t.string :token, null: false

      t.datetime :sent_at
      t.datetime :accepted_at
      t.datetime :expires_at, null: false

      t.timestamps

      t.index :token, unique: true
      t.index [:account_id, :patient_id]
    end
  end
end
