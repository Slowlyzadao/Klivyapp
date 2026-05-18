class HelpFaq < ApplicationRecord
  validates :question, presence: true, length: { maximum: 500 }
  validates :answer, presence: true
  validates :category, presence: true
  validate :category_must_be_valid

  scope :visible, -> { where(hidden: false) }
  scope :ordered, -> { order(:position, :id) }
  scope :by_category, ->(slug) { where(category: slug) }

  def tags_array
    tags.to_s.split(',').map(&:strip).reject(&:empty?)
  end

  private

  def category_must_be_valid
    return if category.blank?

    valid_slugs = HelpCategory.pluck(:slug)
    return if valid_slugs.include?(category)

    errors.add(:category, 'não é uma categoria válida')
  rescue ActiveRecord::StatementInvalid
    nil
  end
end
