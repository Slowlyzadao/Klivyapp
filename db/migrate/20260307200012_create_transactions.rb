class CreateTransactions < ActiveRecord::Migration[7.0]
  def change
    create_table :transactions do |t|
      t.bigint  :account_id,            null: false
      t.bigint  :patient_id,            null: false
      t.bigint  :financial_estimate_id  # FK para o orçamento de origem (opcional)
      t.bigint  :registered_by_id       # usuário que registrou
      t.bigint  :cash_entry_id          # preenchido após baixa dupla (PATCH /pay)

      t.string  :transaction_type,      null: false
      # receita / despesa / reembolso

      t.decimal :amount,                precision: 10, scale: 2, null: false
      t.string  :payment_method
      # pix / cartao_credito / cartao_debito / dinheiro / boleto / transferencia / outros

      t.string  :status,                null: false, default: 'pendente'
      # pendente / pago / vencido / cancelado / reembolsado

      t.date    :due_date
      t.date    :paid_at

      t.text    :description
      t.text    :notes                  # obs internas

      t.integer :installment_number     # 1 de 3 (ex: parcela 1 de 3)
      t.integer :total_installments     # total de parcelas
      # Se > 1, significa que esta transação é uma parcela de um parcelamento

      t.jsonb   :metadata,             default: {}  # dados extras

      t.datetime :deleted_at
      t.timestamps
    end

    add_index :transactions, :account_id
    add_index :transactions, :patient_id
    add_index :transactions, :financial_estimate_id
    add_index :transactions, :status
    add_index :transactions, :due_date
    add_index :transactions, :cash_entry_id
    add_index :transactions, :deleted_at
  end
end
