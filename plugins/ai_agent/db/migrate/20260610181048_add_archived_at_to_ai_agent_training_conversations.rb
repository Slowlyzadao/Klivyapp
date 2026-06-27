class AddArchivedAtToAiAgentTrainingConversations < ActiveRecord::Migration[7.1]
  def change
    # "Excluir só a conversa" arquiva (esconde da lista) preservando as FAQs já
    # aprovadas — que continuam na aba "FAQs aprovadas" e no RAG da Bea.
    add_column :ai_agent_training_conversations, :archived_at, :datetime
  end
end
