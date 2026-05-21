class FinancialCategory < ApplicationRecord
  belongs_to :account
  belongs_to :parent, class_name: 'FinancialCategory', optional: true
  has_many :children, class_name: 'FinancialCategory', foreign_key: :parent_id, dependent: :nullify
  has_many :account_transactions, foreign_key: :financial_category_id, dependent: :nullify
  has_many :commission_rules, foreign_key: :financial_category_id, dependent: :nullify
  has_many :recurring_expenses, foreign_key: :financial_category_id, dependent: :nullify

  validates :name, presence: true
  validates :category_type, presence: true, inclusion: { in: %w[income expense] }
  validates :cost_type, inclusion: { in: %w[fixo variavel] }, allow_nil: true

  scope :active, -> { where.not(id: nil) }
  scope :roots, -> { where(parent_id: nil) }
  scope :income, -> { where(category_type: 'income') }
  scope :expense, -> { where(category_type: 'expense') }
  scope :defaults, -> { where(is_default: true) }
  scope :ordered, -> { order(:position, :name) }

  def root?
    parent_id.nil?
  end
end
