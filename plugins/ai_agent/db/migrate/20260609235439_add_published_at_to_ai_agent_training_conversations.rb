class AddPublishedAtToAiAgentTrainingConversations < ActiveRecord::Migration[7.1]
  def change
    # Marca quando as FAQs aprovadas foram publicadas no RAG da Bea.
    add_column :ai_agent_training_conversations, :published_at, :datetime
  end
end
