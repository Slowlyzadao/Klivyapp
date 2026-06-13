# Looks up the account's knowledge base (RAG) to ground answers in
# uploaded documents. The agent should call this whenever the user asks
# about clinic policy, hours, services, payment, etc.
class AiAgent::Tools::SearchKnowledgeTool < AiAgent::Tools::BaseTool
  description <<~DESC
    Busca na base de conhecimento da clínica (documentos enviados, FAQs)
    por trechos relevantes para responder a pergunta do usuário. Use sempre
    que a pergunta envolver políticas, horários, serviços, valores,
    convênios ou qualquer informação que possa estar nos documentos.
  DESC

  param :query,
        type: :string,
        desc: 'A pergunta ou termo de busca em linguagem natural.'

  def execute(query:)
    retriever = AiAgent::Rag::Retriever.new(account, parent_limit: 4)
    hits = retriever.call(query)

    return { found: false, message: 'Nenhum trecho relevante encontrado.' } if hits.empty?

    {
      found: true,
      excerpts: hits.map do |hit|
        {
          content: hit.parent_chunk.content,
          relevance: (1.0 - hit.best_distance.to_f).round(3),
          document_id: hit.parent_chunk.document_id
        }
      end
    }
  rescue AiAgent::Llm::EmbeddingClient::EmbeddingError => e
    { error: "embedding failed: #{e.message}" }
  end
end
