class CreateConsentRecords < ActiveRecord::Migration[7.0]
  def change
    create_table :consent_records do |t|
      t.bigint  :patient_id,         null: false
      t.bigint  :account_id,         null: false
      t.bigint  :form_template_id                         # template do termo de consentimento
      t.bigint  :created_by_id                            # quem criou o requerimento

      t.string  :title,              null: false           # ex: "Termo de Consentimento — Toxina Botulínica"
      t.string  :status,             default: 'pendente'   # pendente/assinado_localmente/assinado_remotamente/vencido/revogado
      t.string  :mode                                      # local_tablet / remote_link

      # Dados da assinatura
      t.text    :signature_blob                            # base64 PNG da assinatura
      t.string  :integrity_hash                            # SHA-256(patient_id+consent_id+blob+signed_at)
      t.string  :ip_address
      t.string  :device_info
      t.datetime :signed_at

      # Controle de validade
      t.integer :expires_after_days                        # ex: 365 para consentimento anual
      t.datetime :expires_at                               # calculado: signed_at + expires_after_days

      # Link de assinatura remota
      t.string :remote_token                              # token único para link externo
      t.datetime :remote_link_sent_at
      t.datetime :remote_link_expires_at

      t.datetime :deleted_at                               # soft delete OBRIGATÓRIO

      t.timestamps
    end

    add_index :consent_records, :patient_id
    add_index :consent_records, :account_id
    add_index :consent_records, :form_template_id
    add_index :consent_records, :status
    add_index :consent_records, :deleted_at
    add_index :consent_records, :remote_token, unique: true, where: 'remote_token IS NOT NULL'
    add_index :consent_records, [:patient_id, :status]
    add_index :consent_records, :expires_at
  end
end
