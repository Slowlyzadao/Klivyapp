class CreateInstallments < ActiveRecord::Migration[7.0]
  def change
    create_table :installments do |t|
      t.bigint  :account_id,       null: false
      t.bigint  :patient_id,       null: false
      t.bigint  :transaction_id,   null: false  # FK para a transação pai

      t.integer :number,           null: false  # número da parcela (1, 2, 3...)
      t.decimal :amount,           precision: 10, scale: 2, null: false
      t.string  :status,           null: false, default: 'pendente'
      # pendente / pago / vencido / cancelado

      t.date    :due_date,         null: false
      t.date    :paid_at
      t.string  :payment_method    # pode diferir do método da transação pai

      t.bigint  :cash_entry_id     # preenchido após baixa
      t.bigint  :registered_by_id  # quem deu a baixa

      t.text    :notes

      t.datetime :deleted_at
      t.timestamps
    end

    add_index :installments, :account_id
    add_index :installments, :patient_id
    add_index :installments, :transaction_id
    add_index :installments, :status
    add_index :installments, :due_date
    add_index :installments, :cash_entry_id
  end
end
