class AddPaymentSourceToAccountTransactions < ActiveRecord::Migration[7.1]
  VALID_SOURCES = %w[particular convenio plano outro].freeze

  def change
    add_column :account_transactions, :payment_source, :string

    add_check_constraint(
      :account_transactions,
      "payment_source IS NULL OR payment_source IN ('particular', 'convenio', 'plano', 'outro')",
      name: 'chk_account_transactions_payment_source'
    )

    add_index :account_transactions, :payment_source,
              name: 'index_account_transactions_on_payment_source'
  end
end
