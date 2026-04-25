class CommissionRule < ApplicationRecord
  belongs_to :account
  belongs_to :professional, class_name: 'User', foreign_key: :professional_id
  belongs_to :financial_category, optional: true

  COMMISSION_TYPES = %w[percentage_production percentage_received fixed_value].freeze

  validates :commission_type, presence: true, inclusion: { in: COMMISSION_TYPES }
  validates :value, presence: true, numericality: { greater_than: 0 }
  validate :valid_until_after_valid_from

  scope :active, -> { where(active: true) }
  scope :for_professional, ->(user_id) { where(professional_id: user_id) }
  scope :currently_valid, lambda {
    today = Date.today
    active
      .where('valid_from IS NULL OR valid_from <= ?', today)
      .where('valid_until IS NULL OR valid_until >= ?', today)
  }

  # Regra de prioridade: procedimento > categoria > geral
  # Retorna a regra mais específica para um profissional/procedimento/categoria
  def self.most_specific_for(professional_id:, procedure_name: nil, category_id: nil)
    rules = currently_valid.for_professional(professional_id)

    # 1. Prioridade máxima: por procedimento específico
    if procedure_name.present?
      rule = rules.find_by(procedure_name: procedure_name)
      return rule if rule
    end

    # 2. Prioridade média: por categoria
    if category_id.present?
      rule = rules.find_by(financial_category_id: category_id, procedure_name: nil)
      return rule if rule
    end

    # 3. Regra geral (sem especialização)
    rules.find_by(procedure_name: nil, financial_category_id: nil)
  end

  private

  def valid_until_after_valid_from
    return unless valid_from.present? && valid_until.present?

    errors.add(:valid_until, 'deve ser posterior a valid_from') if valid_until < valid_from
  end
end
