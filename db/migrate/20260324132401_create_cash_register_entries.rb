class CreateCashRegisterEntries < ActiveRecord::Migration[7.0]
  def change
    create_table :cash_register_entries do |t|
      t.references :cash_register, null: false, foreign_key: true
      t.references :account,       null: false, foreign_key: true

      t.string  :entry_type,    null: false
                                # supplement | withdrawal | note
      t.decimal :amount,        null: false, precision: 10, scale: 2
      t.string  :payment_method # cash | card_credit | card_debit | pix | transfer | check
      t.text    :description

      t.timestamps
    end

    add_index :cash_register_entries, %i[cash_register_id entry_type],
              name: 'idx_cash_reg_entries_register_type'
  end
end
