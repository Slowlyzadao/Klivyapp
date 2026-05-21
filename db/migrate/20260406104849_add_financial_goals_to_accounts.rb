class AddFinancialGoalsToAccounts < ActiveRecord::Migration[7.1]
  def change
    add_column :accounts, :quarterly_goal, :decimal, precision: 12, scale: 2, default: 0, null: false
    add_column :accounts, :annual_goal, :decimal, precision: 12, scale: 2, default: 0, null: false
  end
end
