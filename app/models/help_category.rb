class HelpCategory < ApplicationRecord
  validates :name, :slug, presence: true
  validates :slug, uniqueness: true

  scope :ordered, -> { order(:position, :name) }
  scope :visible, -> { where(hidden: false) }
end
