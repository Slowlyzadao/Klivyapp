class HelpArticle < ApplicationRecord
  CATEGORIES = %w[conversas agenda pacientes financeiro bea configuracoes outro].freeze
  STATUSES   = %w[published draft].freeze

  validates :title,  presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :category, presence: true
  validate  :category_must_be_valid

  def category_must_be_valid
    valid_slugs = HelpCategory.pluck(:slug)
  rescue StandardError
    valid_slugs = CATEGORIES
  ensure
    errors.add(:category, 'não é uma categoria válida') unless (valid_slugs || CATEGORIES).include?(category.to_s)
  end

  scope :published,   -> { where(status: 'published', deleted_at: nil) }
  scope :by_category, ->(cat) { where(category: cat) }
  scope :visible,     -> { where(deleted_at: nil) }
  scope :ordered,     -> { order(:category, :position, :created_at) }

  def self.search(query)
    q = "%#{query.to_s.downcase}%"
    visible.where('LOWER(title) LIKE ? OR LOWER(body) LIKE ?', q, q)
  end

  def reading_time
    words = body.to_s.gsub(/<[^>]*>/, ' ').split.length
    minutes = (words / 200.0).ceil
    minutes <= 1 ? 'Leitura rápida' : "#{minutes} min de leitura"
  end

  def soft_delete!
    update!(deleted_at: Time.current)
  end
end
