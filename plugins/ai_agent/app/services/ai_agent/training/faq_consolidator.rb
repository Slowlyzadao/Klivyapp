# Estágio 5 — Consolidação. Junta as FAQs extraídas de todos os blocos,
# deduplica perguntas semanticamente parecidas (embedding + similaridade de
# cosseno, reusando o AiAgent::Llm::EmbeddingClient com cache) e ordena por
# categoria. O resultado é a lista de FAQs sugeridas, pendentes de aprovação.
class AiAgent::Training::FaqConsolidator
  # Acima deste cosseno, duas perguntas são consideradas a mesma.
  SIMILARITY_THRESHOLD = 0.92

  def self.call(faqs:)
    new(faqs).call
  end

  def initialize(faqs)
    @faqs = faqs
  end

  def call
    dedup(@faqs).sort_by { |faq| faq['categoria'].to_s }
  end

  private

  def dedup(faqs)
    accepted = []
    accepted_embeddings = []

    faqs.each do |faq|
      question = faq['pergunta_paciente'].to_s
      next if question.blank?

      embedding = embedder.embed(question)
      next if embedding.blank?

      accept_or_replace(accepted, accepted_embeddings, faq, embedding)
    end

    accepted
  rescue AiAgent::Llm::EmbeddingClient::EmbeddingError => e
    # Sem embeddings (provider fora): cai para dedup textual simples (também
    # mantendo a última ocorrência de cada pergunta).
    Rails.logger.warn("[AiAgent::Training::FaqConsolidator] embedding indisponível, dedup textual: #{e.message}")
    faqs.reverse.uniq { |faq| faq['pergunta_paciente'].to_s.downcase.gsub(/\s+/, ' ').strip }.reverse
  end

  def embedder
    @embedder ||= AiAgent::Llm::EmbeddingClient.new
  end

  # Duplicata fica com a versão mais RECENTE: os blocos vêm em ordem
  # cronológica, então quando a atendente se corrige na conversa ("na verdade
  # é R$ 300"), a resposta atual substitui a superada.
  def accept_or_replace(accepted, accepted_embeddings, faq, embedding)
    existing = duplicate_index(embedding, accepted_embeddings)
    if existing
      accepted[existing] = faq
      accepted_embeddings[existing] = embedding
    else
      accepted << faq
      accepted_embeddings << embedding
    end
  end

  def duplicate_index(embedding, others)
    others.index { |existing| AiAgent::Llm::EmbeddingClient.cosine(embedding, existing) >= SIMILARITY_THRESHOLD }
  end
end
