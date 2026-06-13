# Granular block (~300 chars) carrying an embedding for similarity search.
# On retrieval, we look up child chunks then promote to their parents.
class AiAgent::ChildChunk < ApplicationRecord
  self.table_name = 'ai_agent_child_chunks'

  belongs_to :parent_chunk, class_name: 'AiAgent::ParentChunk'
  belongs_to :document, class_name: 'AiAgent::Document'
  belongs_to :account

  has_neighbors :embedding if respond_to?(:has_neighbors)

  validates :content, presence: true
  validates :position, presence: true, uniqueness: { scope: :parent_chunk_id }

  before_save :recompute_char_count

  # Vector similarity search. Returns children ordered by cosine distance.
  # Uses raw SQL because not every Rails app has the `neighbor` gem wired up.
  def self.nearest_to(embedding_vector, scope:, limit: 20)
    vec_literal = "'[#{embedding_vector.join(',')}]'::vector"
    scope
      .where.not(embedding: nil)
      .select("ai_agent_child_chunks.*, embedding <=> #{vec_literal} AS distance")
      .order(Arel.sql("embedding <=> #{vec_literal}"))
      .limit(limit)
  end

  private

  def recompute_char_count
    self.char_count = content.to_s.length
  end
end
