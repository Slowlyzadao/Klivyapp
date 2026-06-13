# Pipeline: extract text → split into parent/child chunks → embed children →
# persist the whole tree atomically.
#
# Re-running on the same document deletes the previous chunks first, so
# editing a source PDF and reprocessing produces a clean result.
class AiAgent::IngestDocumentJob < ApplicationJob
  queue_as :low

  def perform(document_id)
    document = AiAgent::Document.find(document_id)
    document.update!(status: :processing, error_message: nil)

    text = AiAgent::Documents::TextExtractor.new(document).call
    raise 'no text extracted' if text.blank?

    result = AiAgent::Rag::Chunker.new(text).call

    # PERF-21 (auditoria 2026-05-18): embeddings agora rodam FORA da
    # transação, e o cache é checado em batch (1 Redis MGET vs N GETs).
    # Antes: N HTTP requests + N Redis GETs INSIDE a transaction → segurava
    # conexão DB durante toda a latência de rede. Em docs grandes
    # (50+ chunks × 200ms HTTP = 10s+ de conexão DB ociosa).
    embedding_client = AiAgent::Llm::EmbeddingClient.new
    all_children = result.parents.flat_map(&:children)
    child_texts = all_children.map(&:content)
    embeddings = embedding_client.embed_batch(child_texts)
    # Mapa child_block.object_id → embedding pra reaproveitar dentro da
    # transação. object_id é estável pq são os mesmos objetos do array.
    embedding_by_child = all_children.zip(embeddings).to_h

    child_count = 0
    ActiveRecord::Base.transaction do
      document.parent_chunks.destroy_all

      result.parents.each do |parent_block|
        parent = document.parent_chunks.create!(
          position: parent_block.position,
          content: parent_block.content
        )

        parent_block.children.each do |child_block|
          AiAgent::ChildChunk.create!(
            parent_chunk: parent,
            document: document,
            account_id: document.account_id,
            position: child_block.position,
            content: child_block.content,
            embedding: embedding_by_child[child_block]
          )
          child_count += 1
        end
      end

      document.update!(
        status: :processed,
        char_count: text.length,
        parent_chunk_count: result.parents.size,
        child_chunk_count: child_count,
        processed_at: Time.current
      )
    end
  rescue StandardError => e
    Rails.logger.error("[AiAgent::IngestDocumentJob] #{e.class}: #{e.message}")
    AiAgent::Document.find(document_id).update!(
      status: :failed,
      error_message: "#{e.class}: #{e.message}"
    )
    raise
  end
end
