class AiAgent::Feedback < ApplicationRecord
  self.table_name = 'ai_agent_feedbacks'

  belongs_to :account
  belongs_to :trace, class_name: 'AiAgent::Trace', optional: true

  THUMBS_UP = 1
  THUMBS_DOWN = -1

  validates :rating, inclusion: { in: [THUMBS_UP, THUMBS_DOWN] }

  scope :positive, -> { where(rating: THUMBS_UP) }
  scope :negative, -> { where(rating: THUMBS_DOWN) }

  def positive? = rating == THUMBS_UP
  def negative? = rating == THUMBS_DOWN
end
