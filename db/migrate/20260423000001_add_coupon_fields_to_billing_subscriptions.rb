class AddCouponFieldsToBillingSubscriptions < ActiveRecord::Migration[7.1]
  def change
    add_column :billing_subscriptions, :coupon_code, :string
    add_column :billing_subscriptions, :coupon_expires_at, :datetime

    add_index :billing_subscriptions, :coupon_expires_at, where: 'coupon_expires_at IS NOT NULL'
  end
end
