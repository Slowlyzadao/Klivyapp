class AddCreditCardTokenToBillingSubscriptions < ActiveRecord::Migration[7.1]
  def change
    add_column :billing_subscriptions, :asaas_credit_card_token, :string
  end
end
