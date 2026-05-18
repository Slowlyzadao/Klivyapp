class HelpArticle < ApplicationRecord
  STATUSES = %w[draft published].freeze

  validates :title, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :category, presence: true
  validate :category_must_be_valid

  scope :visible,    -> { where(deleted_at: nil) }
  scope :published,  -> { visible.where(status: 'published') }
  scope :by_category, ->(slug) { where(category: slug) }
  scope :ordered,    -> { order(:position, :id) }

  def self.search(query)
    return all if query.blank?

    term = "%#{query}%"
    where('title ILIKE :q OR body ILIKE :q OR category ILIKE :q', q: term)
  end

  def soft_delete!
    update!(deleted_at: Time.current)
  end

  def reading_time
    words = body.to_s.gsub(/<[^>]*>/, ' ').split.size
    minutes = (words / 220.0).ceil
    minutes <= 1 ? 'Leitura rápida' : "#{minutes} min"
  end

  private

  def category_must_be_valid
    return if category.blank?

    valid_slugs = HelpCategory.pluck(:slug)
    return if valid_slugs.include?(category)

    errors.add(:category, 'não é uma categoria válida')
  rescue ActiveRecord::StatementInvalid
    # help_categories table not yet migrated — allow any string until migration runs.
    nil
  end
end
