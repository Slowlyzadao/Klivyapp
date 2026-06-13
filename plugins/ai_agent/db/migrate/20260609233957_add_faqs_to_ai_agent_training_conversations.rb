class AddFaqsToAiAgentTrainingConversations < ActiveRecord::Migration[7.1]
  def change
    # FAQs geradas (estágios 3-5), guardadas como sugestões pendentes de
    # aprovação para revisão na aba "Treinamento". Cada item:
    # { pergunta_paciente, resposta_clinica, categoria, fonte }.
    add_column :ai_agent_training_conversations, :faqs, :jsonb, default: []
  end
end
