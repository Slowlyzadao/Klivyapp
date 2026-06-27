class AiAgent::UsageCounter < ApplicationRecord
  self.table_name = 'ai_agent_usage_counters'

  belongs_to :account

  validates :date, presence: true
  validates :account_id, uniqueness: { scope: :date }

  def self.bump!(account_id:, input_tokens: 0, output_tokens: 0, cost_cents: 0,
                 conversations: 0, tool_calls: 0, on: Date.current)
    counter = find_or_create_by!(account_id: account_id, date: on)
    counter.class.where(id: counter.id).update_all([
                                                     'input_tokens = input_tokens + ?, ' \
                                                     'output_tokens = output_tokens + ?, ' \
                                                     'cost_cents = cost_cents + ?, ' \
                                                     'conversations_count = conversations_count + ?, ' \
                                                     'tool_calls_count = tool_calls_count + ?, ' \
                                                     'updated_at = ?',
                                                     input_tokens, output_tokens, cost_cents, conversations, tool_calls, Time.current
                                                   ])
  end

  def self.monthly_total(account_id:, on: Date.current)
    where(account_id: account_id, date: on.all_month).sum(
      'input_tokens + output_tokens'
    )
  end

  def self.monthly_cost_cents(account_id:, on: Date.current)
    where(account_id: account_id, date: on.all_month).sum(:cost_cents)
  end
end
