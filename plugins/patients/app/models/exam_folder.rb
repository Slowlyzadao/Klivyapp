class ExamFolder < ApplicationRecord
  belongs_to :patient
  belongs_to :account
  belongs_to :parent, class_name: 'ExamFolder', optional: true
  has_many :children, class_name: 'ExamFolder', foreign_key: :parent_id, dependent: :destroy
  has_many :exam_medias, dependent: :nullify

  validates :name, presence: true

  scope :ordered, -> { order(position: :asc) }
  scope :roots, -> { where(parent_id: nil) }
end
