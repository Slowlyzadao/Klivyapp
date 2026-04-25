class SubscriptionPlan < ApplicationRecord
  validates :name, presence: true
  validates :price_monthly, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :display_order, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :slug, presence: true, uniqueness: true

  before_validation :generate_slug

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:display_order, :name) }

  def as_json(options = {})
    super(options).merge(
      'price_monthly' => price_monthly.to_f,
      'price_yearly'  => price_yearly&.to_f
    )
  end

  private

  def generate_slug
    return if slug.present?
    base = name.to_s.parameterize
    return if base.blank?
    candidate = base
    n = 1
    while SubscriptionPlan.where(slug: candidate).where.not(id: id).exists?
      candidate = "#{base}-#{n}"
      n += 1
    end
    self.slug = candidate
  end
end
