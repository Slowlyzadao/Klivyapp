class CreateFinancialCategories < ActiveRecord::Migration[7.0]
  def change
    create_table :financial_categories do |t|
      t.bigint  :account_id,    null: false
      t.string  :name,          null: false
      t.string  :category_type, null: false  # 'income' / 'expense'
      t.string  :cost_type                   # 'fixo' / 'variavel' (para DRE)
      t.bigint  :parent_id                   # subcategoria
      t.string  :color,         default: '#64748b'
      t.string  :icon,          default: 'i-lucide-tag'
      t.boolean :is_default,    default: false
      t.integer :position,      default: 0
      t.timestamps
    end

    add_index :financial_categories, :account_id
    add_index :financial_categories, :category_type
    add_index :financial_categories, :parent_id
    add_index :financial_categories, [:account_id, :category_type]
  end
end
