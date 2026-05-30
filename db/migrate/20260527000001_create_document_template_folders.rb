# Cria a tabela de pastas que organiza os DocumentTemplates dentro de uma
# clínica. Schema suporta hierarquia (parent_id), mas o MVP da UI só usa
# pastas na raiz — subpastas ficam pra Fase 2 se houver demanda.
#
# Plugin: document_templates (Fase 1).
class CreateDocumentTemplateFolders < ActiveRecord::Migration[7.1]
  def change
    create_table :document_template_folders do |t|
      t.references :account, null: false, foreign_key: true, index: true
      t.references :parent,
                   foreign_key: { to_table: :document_template_folders },
                   index: true
      t.string  :name,     null: false, limit: 120
      t.integer :position, null: false, default: 0
      t.string  :color,    limit: 16   # opcional: cor da pasta no UI
      t.string  :icon,     limit: 32   # opcional: ícone lucide (ex: 'folder-heart')
      t.timestamps
    end

    add_index :document_template_folders,
              [:account_id, :parent_id, :position],
              name: 'idx_doc_tpl_folders_account_parent_position'

    # Nome único por raiz da clínica (pasta na raiz não pode ter duplicata).
    # Subpastas (parent_id IS NOT NULL) podem ter mesmo nome em pais
    # diferentes — restrição relaxada propositalmente.
    add_index :document_template_folders,
              [:account_id, :name],
              unique: true,
              where: 'parent_id IS NULL',
              name: 'idx_doc_tpl_folders_unique_root_name_per_account'
  end
end
