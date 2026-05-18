module AiAgent
  class PersonaTemplate < ApplicationRecord
    self.table_name = 'ai_agent_persona_templates'

    VERTICALS = %w[dental aesthetic wellness general].freeze

    validates :name, presence: true, uniqueness: true
    validates :vertical, inclusion: { in: VERTICALS }
    validates :system_prompt, presence: true
  end
end
