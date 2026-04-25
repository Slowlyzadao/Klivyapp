class CreateBankAccounts < ActiveRecord::Migration[7.0]
  def change
    create_table :bank_accounts do |t|
      t.bigint  :account_id,      null: false
      t.string  :name,            null: false        # "Caixa", "Bradesco PJ"
      t.string  :bank_name                           # "Bradesco", "Itaú"
      t.string  :bank_code                           # "237"
      t.string  :account_type,    default: 'checking' # checking / savings / cash
      t.decimal :initial_balance, precision: 12, scale: 2, default: 0.0
      t.boolean :active,          default: true
      t.timestamps
    end

    add_index :bank_accounts, :account_id
    add_index :bank_accounts, [:account_id, :active]
  end
end
