# Detecta perguntas SEMANTICAMENTE duplicadas via embedding + cosseno (reusa o
# AiAgent::Llm::EmbeddingClient com cache). Pega casos que o texto não pega —
# ex.: "Quais informações..." vs "Quais dados...". Dois usos:
#   - within:  acha repetições DENTRO de uma lista (FAQs já aprovadas).
#   - against: checa perguntas novas CONTRA um conjunto existente (na aprovação).
# Se o provider de embedding estiver fora, degrada para "nada duplicado".
class AiAgent::Training::DuplicateScanner
  SIMILARITY_THRESHOLD = 0.85

  # Índices de `questions` cuja pergunta é parecida com uma ANTERIOR na lista.
  def self.within(questions)
    embeddings = embed_all(questions)
    dups = Set.new

    embeddings.each_index do |i|
      next if embeddings[i].nil?

      dups << i if (0...i).any? { |j| similar?(embeddings[i], embeddings[j]) }
    end

    dups
  rescue AiAgent::Llm::EmbeddingClient::EmbeddingError
    Set.new
  end

  # Índices de `questions` parecidos com alguma pergunta de `reference`.
  def self.against(questions, reference)
    refs = embed_all(reference).compact
    return Set.new if refs.empty?

    dups = Set.new
    embed_all(questions).each_with_index do |emb, i|
      next if emb.nil?

      dups << i if refs.any? { |r| similar?(emb, r) }
    end

    dups
  rescue AiAgent::Llm::EmbeddingClient::EmbeddingError
    Set.new
  end

  def self.similar?(vec_a, vec_b)
    vec_a && vec_b && AiAgent::Llm::EmbeddingClient.cosine(vec_a, vec_b) >= SIMILARITY_THRESHOLD
  end
  private_class_method :similar?

  def self.embed_all(questions)
    AiAgent::Llm::EmbeddingClient.new.embed_batch(questions.map(&:to_s))
  end
  private_class_method :embed_all
end
