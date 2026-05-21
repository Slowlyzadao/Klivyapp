class HelpCategory < ApplicationRecord
  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true

  scope :ordered, -> { order(:position, :id) }
  scope :visible, -> { where(hidden: false) }
end
