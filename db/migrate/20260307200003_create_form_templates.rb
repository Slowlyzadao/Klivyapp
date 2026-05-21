class CreateFormTemplates < ActiveRecord::Migration[7.0]
  def change
    create_table :form_templates do |t|
      t.bigint  :account_id,    null: false
      t.string  :name,          null: false
      t.string  :template_type, null: false  # anamnesis / clinical_note / consent / document
      t.string  :specialty                   # geral / odontologia / fisioterapia / etc
      t.jsonb   :fields,        default: []  # estrutura dos campos do formulário
      t.boolean :is_global,     default: false  # true = disponível para todas as contas (admin)
      t.boolean :active,        default: true
      t.bigint  :created_by_id
      t.datetime :deleted_at
      t.timestamps null: false
    end

    add_index :form_templates, :account_id
    add_index :form_templates, :template_type
    add_index :form_templates, :specialty
    add_index :form_templates, :is_global
    add_index :form_templates, :active
    add_index :form_templates, :deleted_at
    add_index :form_templates, [:account_id, :template_type, :active]

    add_foreign_key :form_templates, :accounts
  end
end
