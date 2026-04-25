class CreateCashRegisters < ActiveRecord::Migration[7.0]
  def change
    create_table :cash_registers do |t|
      t.references :account,  null: false, foreign_key: true
      t.references :operator, null: false, foreign_key: { to_table: :users }

      t.date   :register_date, null: false
      t.string :status,        null: false, default: 'open'
                               # open | closed

      # Valores de abertura
      t.decimal :opening_balance, precision: 10, scale: 2, null: false, default: 0

      # Movimentações registradas manualmente
      t.decimal :cash_in,  precision: 10, scale: 2, null: false, default: 0
      t.decimal :cash_out, precision: 10, scale: 2, null: false, default: 0

      # Sangrias e suprimentos
      t.decimal :withdrawals,  precision: 10, scale: 2, null: false, default: 0
      t.decimal :supplements,  precision: 10, scale: 2, null: false, default: 0

      # Fechamento
      t.decimal :closing_balance,   precision: 10, scale: 2
      t.decimal :declared_balance,  precision: 10, scale: 2
      t.decimal :difference,        precision: 10, scale: 2
      t.text    :closing_notes

      t.datetime :opened_at
      t.datetime :closed_at

      t.timestamps
    end

    add_index :cash_registers, %i[account_id operator_id register_date],
              name: 'idx_cash_registers_account_operator_date'
    add_index :cash_registers, %i[account_id status],
              name: 'idx_cash_registers_account_status'
    add_index :cash_registers, %i[account_id register_date],
              name: 'idx_cash_registers_account_date'
  end
end
