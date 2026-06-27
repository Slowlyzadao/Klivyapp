# One row per LLM turn. Holds the data needed to answer the questions
# super admins ask after a week in production: how much are we spending,
# which tools are getting called, where are conversations escalating.
class AiAgent::Trace < ApplicationRecord
  self.table_name = 'ai_agent_traces'

  belongs_to :account
  has_many :feedbacks,
           class_name: 'AiAgent::Feedback',
           dependent: :nullify

  scope :for_period, ->(from, to) { where(created_at: from..to) }

  def total_tokens
    input_tokens.to_i + output_tokens.to_i
  end
end
