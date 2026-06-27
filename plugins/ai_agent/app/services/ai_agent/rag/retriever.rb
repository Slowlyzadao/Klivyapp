# Retrieves the most relevant context for a query using parent/child RAG.
#
# Steps:
#   1. embed the query
#   2. find top-K closest child chunks via cosine similarity
#   3. promote each match to its parent chunk (deduped, ordered by best match)
#   4. return parents with their best child distance for traceability
class AiAgent::Rag::Retriever
  Hit = Struct.new(:parent_chunk, :best_distance, :matched_children, keyword_init: true)

  DEFAULT_TOP_K = 8
  DEFAULT_PARENT_LIMIT = 4

  def initialize(account, top_k: DEFAULT_TOP_K, parent_limit: DEFAULT_PARENT_LIMIT)
    @account = account
    @top_k = top_k
    @parent_limit = parent_limit
  end

  def call(query)
    return [] if query.to_s.strip.empty?

    embedding = AiAgent::Llm::EmbeddingClient.new.embed(query)
    return [] if embedding.blank?

    children = AiAgent::ChildChunk.nearest_to(
      embedding,
      scope: account_scope,
      limit: @top_k
    ).to_a

    promote_to_parents(children)
  end

  private

  def account_scope
    AiAgent::ChildChunk.where(account_id: @account.id)
  end

  def promote_to_parents(children)
    grouped = children.group_by(&:parent_chunk_id)

    ranked = grouped.map do |_parent_id, kids|
      best = kids.min_by { |c| c[:distance] || c.attributes['distance'] || Float::INFINITY }
      [best, kids]
    end

    top = ranked.sort_by { |best, _kids| best.attributes['distance'].to_f }
                .first(@parent_limit)

    parent_ids = top.map { |best, _kids| best.parent_chunk_id }
    parents_by_id = parents_scope.where(id: parent_ids).index_by(&:id)

    top.filter_map do |best, kids|
      parent = parents_by_id[best.parent_chunk_id]
      next if parent.nil?

      Hit.new(
        parent_chunk: parent,
        best_distance: best.attributes['distance'].to_f,
        matched_children: kids
      )
    end
  end

  # Defesa contra cross-tenant: ParentChunk não tem account_id direto,
  # então fazemos JOIN com ai_agent_documents.account_id. Garante que
  # nenhum parent_chunk de outro tenant é retornado mesmo se um child
  # passasse pelo scope (defesa em profundidade).
  def parents_scope
    AiAgent::ParentChunk
      .joins(:document)
      .where(ai_agent_documents: { account_id: @account.id })
  end
end
