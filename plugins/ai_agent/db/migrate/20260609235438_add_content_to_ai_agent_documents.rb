class AddContentToAiAgentDocuments < ActiveRecord::Migration[7.1]
  def change
    # Texto puro para Documents de source_type 'text' (ex.: as FAQs publicadas
    # pelo Treinamento da Bea). O AiAgent::IngestDocumentJob chunka/embeda este
    # conteúdo igual faz com PDF/URL.
    add_column :ai_agent_documents, :content, :text
  end
end
