class CreateFinancialEstimates < ActiveRecord::Migration[7.0]
  def change
    create_table :financial_estimates do |t|
      t.bigint  :account_id,       null: false
      t.bigint  :patient_id,       null: false
      t.bigint  :treatment_plan_id
      t.bigint  :generated_by_id   # user que gerou o orçamento

      t.string  :status,           null: false, default: 'rascunho'
      # rascunho / enviado / aprovado / cancelado

      t.decimal :subtotal,         precision: 10, scale: 2, default: 0.0
      t.decimal :discount_amount,  precision: 10, scale: 2, default: 0.0
      t.decimal :total,            precision: 10, scale: 2, default: 0.0
      t.string  :discount_type     # percentual / fixo
      t.decimal :discount_value,   precision: 10, scale: 2, default: 0.0

      t.integer :installments_count, default: 1
      t.string  :payment_method    # pix / cartao / dinheiro / boleto / outros

      t.text    :notes             # observações do orçamento
      t.date    :valid_until       # validade do orçamento

      t.datetime :approved_at
      t.datetime :sent_at

      t.datetime :deleted_at       # soft delete
      t.timestamps
    end

    add_index :financial_estimates, :account_id
    add_index :financial_estimates, :patient_id
    add_index :financial_estimates, :treatment_plan_id
    add_index :financial_estimates, :status
    add_index :financial_estimates, :deleted_at
  end
end
