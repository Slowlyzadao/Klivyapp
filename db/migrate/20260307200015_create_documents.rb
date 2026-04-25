class CreateDocuments < ActiveRecord::Migration[7.0]
  def change
    create_table :documents do |t|
      t.bigint  :patient_id,         null: false
      t.bigint  :account_id,         null: false
      t.bigint  :generated_by_id                        # user que gerou/anexou
      t.bigint  :form_template_id                       # template usado na geração (opcional)

      t.string  :document_type,      null: false        # enum: receita/atestado/pedido_exame/etc
      t.string  :status,             default: 'gerado'  # gerado/pendente_assinatura/assinado/enviado/arquivado
      t.string  :title,              null: false         # nome legível do documento
      t.integer :version,            default: 1         # versionamento — nunca sobrescrever
      t.boolean :is_generated,       default: false     # true = gerado pelo servidor, false = upload externo

      # Para documentos gerados server-side (Prawn)
      t.jsonb   :variables,          default: {}        # variáveis do template preenchidas

      t.string  :file_name
      t.string  :mime_type
      t.bigint  :file_size

      t.datetime :sent_at                               # quando foi enviado (WhatsApp/email)
      t.datetime :signed_at                             # quando foi assinado
      t.bigint :signed_by_id                           # quem assinou

      t.datetime :deleted_at                            # soft delete OBRIGATÓRIO

      t.timestamps
    end

    add_index :documents, :patient_id
    add_index :documents, :account_id
    add_index :documents, :form_template_id
    add_index :documents, :document_type
    add_index :documents, :status
    add_index :documents, :deleted_at
    add_index :documents, [:patient_id, :document_type]
  end
end
