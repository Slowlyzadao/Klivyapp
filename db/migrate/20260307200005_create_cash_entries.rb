class CreateCashEntries < ActiveRecord::Migration[7.0]
  def change
    create_table :cash_entries do |t|
      t.bigint   :account_id,      null: false
      t.string   :entry_type,      null: false   # income / expense / refund
      t.decimal  :amount,          precision: 10, scale: 2, null: false
      t.string   :description
      t.string   :source_type                    # "Transaction", "manual" (polimórfico)
      t.bigint   :source_id                      # FK polimórfico para Transaction (Bloco 4)
      t.string   :payment_method                 # pix / cartao / dinheiro / boleto / outros
      t.date     :entry_date,      null: false
      t.bigint   :patient_id                     # referência ao paciente (opcional)
      t.bigint   :registered_by_id               # user que registrou
      t.jsonb    :metadata,        default: {}   # dados extras para módulo Financeiro Mestre
      t.datetime :deleted_at
      t.timestamps null: false
    end

    add_index :cash_entries, :account_id
    add_index :cash_entries, :patient_id
    add_index :cash_entries, :entry_date
    add_index :cash_entries, :entry_type
    add_index :cash_entries, :payment_method
    add_index :cash_entries, [:source_type, :source_id]
    add_index :cash_entries, [:account_id, :entry_date]
    add_index :cash_entries, :deleted_at

    add_foreign_key :cash_entries, :accounts
  end
end
