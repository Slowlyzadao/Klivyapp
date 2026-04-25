class AddDiscountAmountToDiscountCoupons < ActiveRecord::Migration[7.0]
  def change
    add_column :discount_coupons, :discount_amount, :decimal, precision: 10, scale: 2
  end
end
