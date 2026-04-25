class CreateBillingTables < ActiveRecord::Migration[7.0]
  def change
    create_table :billing_customers do |t|
      t.string :name, null: false
      t.string :email, null: false
      t.string :cpf_cnpj
      t.string :phone
      t.string :asaas_customer_id

      t.timestamps
    end

    create_table :billing_subscriptions do |t|
      t.references :account, null: false, foreign_key: true
      t.integer :status, default: 0, null: false # enum for trial, pending, active, overdue, canceled
      t.string :plan
      t.decimal :price, precision: 10, scale: 2
      t.string :asaas_customer_id
      t.string :asaas_subscription_id
      t.datetime :next_due_date

      t.timestamps
    end

    create_table :billing_payments do |t|
      t.references :subscription, null: false, foreign_key: { to_table: :billing_subscriptions }
      t.integer :status, default: 0, null: false
      t.decimal :amount, precision: 10, scale: 2
      t.datetime :due_date
      t.datetime :paid_at
      t.string :asaas_payment_id

      t.timestamps
    end
  end
end
