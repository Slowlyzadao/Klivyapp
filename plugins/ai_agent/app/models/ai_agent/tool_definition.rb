class AiAgent::ToolDefinition < ApplicationRecord
  self.table_name = 'ai_agent_tool_definitions'

  validates :key, presence: true, uniqueness: true
  validates :name, presence: true

  scope :enabled, -> { where(enabled_globally: true) }
end
