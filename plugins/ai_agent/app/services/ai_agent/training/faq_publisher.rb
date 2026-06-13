# Publicação — pega as FAQs aprovadas de uma conversa de treinamento, formata
# como texto e cria um AiAgent::Document de source_type 'text'. O
# AiAgent::IngestDocumentJob então chunka/embeda esse texto no RAG da Bea — de
# onde o SearchKnowledgeTool busca em runtime.
#
# Idempotente: re-publicar (depois de editar/apagar uma FAQ) remove a versão
# anterior do RAG antes de recriar. Lista vazia = despublica (sai do RAG).
class AiAgent::Training::FaqPublisher
  def self.call(training:, faqs:)
    new(training, faqs).call
  end

  def initialize(training, faqs)
    @training = training
    @faqs = Array(faqs)
  end

  def call
    remove_previous_document

    return unpublish if @faqs.empty?

    document = AiAgent::Document.create!(
      account: @training.account,
      name: document_name,
      source_type: 'text',
      content: render_content
    )
    AiAgent::IngestDocumentJob.perform_later(document.id)
    @training.update!(
      published_at: Time.current,
      faqs: @faqs,
      faq_count: @faqs.size,
      published_document_id: document.id
    )
    document
  end

  private

  def unpublish
    @training.update!(published_at: nil, faqs: [], faq_count: 0, published_document_id: nil)
    nil
  end

  # Remove do RAG o Document publicado anteriormente (e seus chunks).
  def remove_previous_document
    doc_id = @training.published_document_id
    return if doc_id.blank?

    parent_ids = AiAgent::ParentChunk.where(document_id: doc_id).pluck(:id)
    AiAgent::ChildChunk.where(parent_chunk_id: parent_ids).delete_all
    AiAgent::ParentChunk.where(document_id: doc_id).delete_all
    AiAgent::Document.where(id: doc_id).delete_all
  end

  def document_name
    "Treinamento: #{@training.name}".first(255)
  end

  # Formato "P:/R:" com a categoria como prefixo — o RAG Chunker fatia isto em
  # chunks pesquisáveis.
  def render_content
    @faqs.map do |faq|
      categoria = faq['categoria'].to_s.strip
      header = categoria.present? ? "[#{categoria}] " : ''
      "#{header}P: #{faq['pergunta_paciente']}\nR: #{faq['resposta_clinica']}"
    end.join("\n\n")
  end
end
