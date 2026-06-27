# Singleton — there is only one row holding the global Bea configuration
# editable by super admins. Never instantiate directly; always use `current`.
class AiAgent::GlobalSetting < ApplicationRecord
  self.table_name = 'ai_agent_global_settings'

  belongs_to :default_persona,
             class_name: 'AiAgent::PersonaTemplate',
             optional: true

  VALID_PROVIDERS = %w[openai gemini].freeze

  validates :chat_provider, inclusion: { in: VALID_PROVIDERS }
  validates :max_tokens_per_conversation, numericality: { greater_than: 0 }
  validates :max_monthly_cost_per_account_cents, numericality: { greater_than_or_equal_to: 0 }

  def self.current
    first_or_create!
  end

  # 0 means "no cap"
  def unlimited_monthly_cost?
    max_monthly_cost_per_account_cents.zero?
  end
end
