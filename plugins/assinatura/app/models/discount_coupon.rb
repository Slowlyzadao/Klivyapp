class DiscountCoupon < ApplicationRecord
  KINDS = %w[trial percent fixed_value free_forever].freeze

  validates :code, presence: true, uniqueness: { case_sensitive: false }
  validates :description, presence: true
  validates :kind, presence: true, inclusion: { in: KINDS }
  validates :discount_percent, presence: true, numericality: { in: 1..100 }, if: -> { kind == 'percent' }
  validates :discount_amount, presence: true, numericality: { greater_than: 0 }, if: -> { kind == 'fixed_value' }
  validates :trial_days, presence: true, numericality: { greater_than: 0, only_integer: true }, if: -> { kind == 'trial' }
  validates :months_duration, presence: true, numericality: { greater_than: 0, only_integer: true }, if: -> { %w[percent fixed_value].include?(kind) }

  before_save { self.code = code.upcase.strip }

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(created_at: :desc) }

  def expired?
    expires_at.present? && expires_at < Time.current
  end

  def uses_exhausted?
    max_uses.present? && current_uses >= max_uses
  end

  def valid_for_use?
    active? && !expired? && !uses_exhausted?
  end
end
