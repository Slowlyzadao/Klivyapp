class CreateDiscountCoupons < ActiveRecord::Migration[7.0]
  def change
    create_table :discount_coupons do |t|
      t.string   :code,             null: false
      t.string   :description,      null: false
      t.string   :kind,             null: false
      t.integer  :discount_percent
      t.integer  :trial_days
      t.integer  :months_duration
      t.boolean  :active,           null: false, default: true
      t.integer  :max_uses
      t.integer  :current_uses,     null: false, default: 0
      t.datetime :expires_at

      t.timestamps
    end

    add_index :discount_coupons, :code, unique: true
    add_index :discount_coupons, :kind
    add_index :discount_coupons, :active
  end
end
