# Overrides por profissional sobre PatientPortalSetting da account.
# Hierarquia de config: Account → Profissional → Serviço → Procedimento → Tag
# (PRD §14.6). `overrides` é jsonb sparse — só chaves sobrescritas ficam aqui.
class CreateProfessionalPortalSettings < ActiveRecord::Migration[7.1]
  def change
    create_table :professional_portal_settings do |t|
      t.references :account, null: false, foreign_key: true
      t.references :user,    null: false, foreign_key: true

      t.jsonb :overrides, null: false, default: {}

      # Opt-in para receber mensagens diretas (Fase 2, mas modelado já)
      t.boolean :accepts_direct_messages, null: false, default: false

      t.timestamps

      t.index [:account_id, :user_id], unique: true, name: 'idx_prof_portal_settings_account_user'
    end
  end
end
