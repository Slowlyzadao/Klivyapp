class CreateSubscriptionPlans < ActiveRecord::Migration[7.0]
  def change
    create_table :subscription_plans do |t|
      t.string  :name,          null: false
      t.text    :description
      t.decimal :price_monthly, null: false, precision: 10, scale: 2, default: 0
      t.decimal :price_yearly,  precision: 10, scale: 2
      t.string  :color,         default: '#5B5BD6'
      t.jsonb   :features,      null: false, default: []
      t.jsonb   :limits,        null: false, default: {}
      t.string  :slug
      t.boolean :active,        null: false, default: true
      t.integer :display_order, null: false, default: 0

      t.timestamps
    end

    add_index :subscription_plans, :active
    add_index :subscription_plans, :display_order
    add_index :subscription_plans, :slug, unique: true
  end
end
