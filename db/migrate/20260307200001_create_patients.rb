class CreatePatients < ActiveRecord::Migration[7.0]
  def change
    create_table :patients do |t|
      t.bigint  :account_id,                null: false
      t.string  :name,                      null: false
      t.string  :phone
      t.string  :email
      t.string  :cpf
      t.string  :rg
      t.date    :birthdate
      t.string  :sex
      t.string  :patient_status,            default: 'novo'
      t.integer :no_show_count,             default: 0
      t.boolean :needs_recall,              default: false
      t.string  :avatar_url
      t.jsonb   :address,                   default: {}
      t.jsonb   :contacts,                  default: []
      t.jsonb   :emergency_contact,         default: {}
      t.jsonb   :insurance,                 default: {}
      t.jsonb   :billing_info,              default: {}
      t.jsonb   :contact_preferences,       default: {}
      t.jsonb   :communication_opt_ins,     default: {}
      t.jsonb   :lgpd_consent,              default: {}
      t.text    :pinned_note
      t.string  :origin
      t.string  :unit
      t.bigint  :responsible_professional_id
      t.bigint  :contact_id    # FK para contacts (ponte com Chatwoot/CW)
      t.datetime :deleted_at   # soft delete OBRIGATÓRIO
      t.timestamps null: false
    end

    add_index :patients, :account_id
    add_index :patients, :cpf
    add_index :patients, :email
    add_index :patients, :phone
    add_index :patients, :patient_status
    add_index :patients, :deleted_at
    add_index :patients, :contact_id
    add_index :patients, [:account_id, :name]
    add_index :patients, [:account_id, :deleted_at]

    add_foreign_key :patients, :accounts
  end
end
