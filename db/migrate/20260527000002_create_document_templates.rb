# Tabela central do plugin document_templates. Cada row é um modelo de
# documento — contrato, atestado, receita, consentimento — escrito no editor
# TipTap e renderizado em PDF via Grover quando usado.
#
# Decisões de schema importantes (alinhamento com auditoria):
#   - account_id é NULLABLE: templates Klivy globais (source='klivy') têm
#     account_id NULL e são visíveis pra todas as clínicas como biblioteca.
#   - document_type é STRING (não enum integer) — espelha Document.document_type
#     que também é string. Valores: 'receita', 'atestado', ..., 'consentimento_lgpd'.
#   - content_json é JSONB contendo o documento ProseMirror serializado
#     (saída do TipTap). É a fonte da verdade; HTML é derivado.
#   - content_html_cached é cache opcional pra preview no admin; NUNCA usado
#     pro PDF final (que sempre rerenderiza com dados do paciente).
class CreateDocumentTemplates < ActiveRecord::Migration[7.1]
  def change
    create_table :document_templates do |t|
      # Account NULL = template Klivy global (visível a todas as clínicas).
      # Account presente = template da clínica (criado ou clonado).
      t.references :account, null: true, foreign_key: true, index: true

      t.references :folder,
                   foreign_key: { to_table: :document_template_folders },
                   index: true

      t.references :created_by_user,
                   foreign_key: { to_table: :users },
                   index: true

      # Quando source='cloned', aponta pro template Klivy original.
      # Permite rastrear "qual template Klivy gerou esse?" e detectar updates
      # da biblioteca pra oferecer "re-importar".
      t.references :source_template,
                   foreign_key: { to_table: :document_templates },
                   index: true

      t.string  :name, null: false, limit: 200
      t.text    :description

      # STRING (não enum integer) — alinhado com Document.document_type.
      # Valores válidos definidos no model em DOCUMENT_TYPES (Fase 1 Models).
      t.string  :document_type, null: false

      # Documento ProseMirror serializado. Exemplo mínimo válido:
      #   { "type": "doc", "content": [{ "type": "paragraph" }] }
      t.jsonb   :content_json, null: false, default: {}

      # Cache opcional de HTML pra preview rápido no admin. Não usar pro PDF.
      t.text    :content_html_cached

      # 'klivy' = template global da Klivy (account_id NULL).
      # 'clinic' = criado do zero pela clínica.
      # 'cloned' = clínica clicou em "Usar este modelo" num Klivy → source_template_id aponta pro Klivy.
      t.string  :source, null: false, default: 'clinic'

      # 'draft' (rascunho — não aparece pros profissionais).
      # 'active' (publicado, pode ser usado pra gerar documento).
      # 'archived' (esconde da UI mas mantém pra documentos antigos).
      t.string  :status, null: false, default: 'active'

      # Incrementa a cada save substancial (lógica no model). Exibido no UI
      # ("v3") pra trilha de auditoria simples. Sem UI de diff no MVP.
      t.integer :version, null: false, default: 1

      t.string  :paper_size,  default: 'A4'         # 'A4' | 'Letter' | 'A5'
      t.string  :orientation, default: 'portrait'   # 'portrait' | 'landscape'
      t.jsonb   :metadata,    default: {}           # extensões futuras (tags, ai_generated, etc.)

      t.datetime :archived_at
      t.timestamps
    end

    # Lookup principal: "templates dessa clínica desse tipo que estão ativos"
    # — usado quando profissional vai gerar documento dentro do paciente.
    add_index :document_templates, [:account_id, :document_type, :status],
              name: 'idx_doc_tpls_account_type_status'

    # Listagem por pasta.
    add_index :document_templates, [:account_id, :folder_id],
              name: 'idx_doc_tpls_account_folder'

    # Lookup dos templates Klivy globais (account_id IS NULL).
    # Index parcial pra reduzir custo de manutenção.
    add_index :document_templates, [:source, :document_type],
              where: 'account_id IS NULL',
              name: 'idx_doc_tpls_klivy_library'

    add_index :document_templates, :archived_at
  end
end
