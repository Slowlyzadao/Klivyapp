module AiAgent
  # Pipeline: extract text → split into parent/child chunks → embed children →
  # persist the whole tree atomically.
  #
  # Re-running on the same document deletes the previous chunks first, so
  # editing a source PDF and reprocessing produces a clean result.
  class IngestDocumentJob < ApplicationJob
    queue_as :low

    def perform(document_id)
      document = AiAgent::Document.find(document_id)
      document.update!(status: :processing, error_message: nil)

      text = AiAgent::Documents::TextExtractor.new(document).call
      raise 'no text extracted' if text.blank?

      result = AiAgent::Rag::Chunker.new(text).call

      embedding_client = AiAgent::Llm::EmbeddingClient.new
      child_count = 0

      ActiveRecord::Base.transaction do
        document.parent_chunks.destroy_all

        result.parents.each do |parent_block|
          parent = document.parent_chunks.create!(
            position: parent_block.position,
            content: parent_block.content
          )

          parent_block.children.each do |child_block|
            embedding = embedding_client.embed(child_block.content)
            AiAgent::ChildChunk.create!(
              parent_chunk: parent,
              document: document,
              account_id: document.account_id,
              position: child_block.position,
              content: child_block.content,
              embedding: embedding
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
end
