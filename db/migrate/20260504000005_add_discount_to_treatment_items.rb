class AddDiscountToTreatmentItems < ActiveRecord::Migration[7.0]
  def change
    change_table :treatment_items, bulk: true do |t|
      # 'fixo' (R$) | 'percentual' (% sobre subtotal)
      t.string  :discount_type
      t.decimal :discount_value, precision: 10, scale: 2, default: 0, null: false
    end
  end
end
