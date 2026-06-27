class AllowNullClinicSenderNameOnAiAgentTrainingConversations < ActiveRecord::Migration[7.1]
  def change
    # Nome da clínica passou a ser opcional na criação: o usuário só escolhe
    # depois, na detecção dos participantes (status awaiting_clinic).
    change_column_null :ai_agent_training_conversations, :clinic_sender_name, true
  end
end
