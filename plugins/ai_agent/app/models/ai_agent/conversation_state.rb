# Short-term memory for one Chatwoot conversation. Holds the rolling summary,
# last detected intent and arbitrary working memory the agent populates
# mid-conversation. Persisted in Postgres (rather than Redis) because the
# rest of the app already speaks AR — no extra infra to keep in sync.
class AiAgent::ConversationState < ApplicationRecord
  self.table_name = 'ai_agent_conversation_states'

  STATUSES = %w[active escalated resolved abandoned].freeze

  belongs_to :account

  validates :conversation_id, presence: true,
                              uniqueness: { scope: :account_id }
  validates :status, inclusion: { in: STATUSES }

  def self.for(account:, conversation_id:)
    find_or_create_by!(account_id: account.id, conversation_id: conversation_id)
  end

  def remember(key, value)
    working_memory[key.to_s] = value
    save!
  end

  def recall(key)
    working_memory[key.to_s]
  end

  def escalate!(reason: nil)
    update!(status: 'escalated', last_intent: reason || last_intent)
  end
end
