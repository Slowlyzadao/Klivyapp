class CreateCommissionRules < ActiveRecord::Migration[7.0]
  def change
    create_table :commission_rules do |t|
      t.bigint  :account_id,           null: false
      t.bigint  :professional_id,      null: false   # user (profissional)
      t.string  :commission_type,      null: false   # 'percentage_production' / 'percentage_received' / 'fixed_value'
      t.decimal :value,                precision: 10, scale: 2, null: false  # % ou R$
      t.bigint  :financial_category_id               # se aplica só a uma categoria (ex: "Procedimentos")
      t.string  :procedure_name                      # se aplica a um procedimento específico (ex: "Clareamento")
      t.string  :specialty                           # se aplica a uma especialidade (ex: "Ortodontia")
      t.date    :valid_from                          # início da vigência
      t.date    :valid_until                         # fim da vigência (null = sempre vigente)
      t.boolean :active,               default: true
      t.text    :notes
      t.timestamps
    end

    add_index :commission_rules, :account_id
    add_index :commission_rules, :professional_id
    add_index :commission_rules, [:account_id, :professional_id]
    add_index :commission_rules, :active
  end
end
