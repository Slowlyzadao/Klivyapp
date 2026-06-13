class AddParticipantsToAiAgentTrainingConversations < ActiveRecord::Migration[7.1]
  def change
    # Participantes detectados na conversa (remetente + contagem de mensagens),
    # para o usuário escolher quem é a clínica antes do processamento pesado.
    add_column :ai_agent_training_conversations, :participants, :jsonb, default: []
  end
end
