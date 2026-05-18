class AddSentimentToConversationStates < ActiveRecord::Migration[7.1]
  def change
    add_column :ai_agent_conversation_states, :last_sentiment_score, :decimal, precision: 4, scale: 3
    add_column :ai_agent_conversation_states, :last_sentiment_label, :string
    add_column :ai_agent_conversation_states, :consecutive_negative_count, :integer, null: false, default: 0
    add_column :ai_agent_conversation_states, :consecutive_tool_failures, :integer, null: false, default: 0
  end
end
