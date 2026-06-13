module Financial
  # Procedimento ou produto dentro de um Budget.
  # NÃO usa soft delete — itens pertencem ao budget e seguem o ciclo dele.
  class BudgetItem < ::ApplicationRecord
    self.table_name = 'financial_budget_items'
    self.inheritance_column = :_type_disabled

    extend Financial::Concerns::MoneyAttribute::ClassMethods

    belongs_to :account, class_name: '::Account'
    belongs_to :budget, class_name: 'Financial::Budget', foreign_key: :financial_budget_id
    belongs_to :professional, class_name: '::User', optional: true
    belongs_to :treatment_item, optional: true

    money_attribute :unit_price_cents, as: :unit_price
    money_attribute :discount_cents,   as: :discount
    money_attribute :total_cents,      as: :total

    validates :description, presence: true, length: { maximum: 240 }
    validates :quantity, numericality: { greater_than: 0, only_integer: true }
    validates :unit_price_cents, numericality: { greater_than_or_equal_to: 0, only_integer: true }

    before_validation :compute_total

    private

    def compute_total
      qty = quantity || 1
      self.total_cents = (unit_price_cents.to_i * qty) - discount_cents.to_i
    end
  end
end
