class HelpFaq < ApplicationRecord
  validates :question, presence: true
  validates :answer,   presence: true
  validates :category, presence: true

  scope :ordered, -> { order(:position, :id) }
  scope :active,  -> { where(active: true) }

  def category_name
    HelpCategory.find_by(slug: category)&.name || category.capitalize
  end
end
