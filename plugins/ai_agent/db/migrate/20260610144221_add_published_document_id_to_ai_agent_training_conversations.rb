class AddPublishedDocumentIdToAiAgentTrainingConversations < ActiveRecord::Migration[7.1]
  def change
    # Vínculo com o AiAgent::Document publicado no RAG — permite re-publicar
    # (ao editar/apagar uma FAQ) sem duplicar, e remover do RAG quando preciso.
    add_column :ai_agent_training_conversations, :published_document_id, :bigint
  end
end
