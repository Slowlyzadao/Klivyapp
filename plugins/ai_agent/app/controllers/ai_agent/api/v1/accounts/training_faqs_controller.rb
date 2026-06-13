# Gestão centralizada das FAQs já publicadas no RAG da Bea. Cada FAQ vive no
# jsonb `faqs` da conversa de treinamento que a originou; aqui o usuário vê
# todas juntas, edita a resposta (ou a pergunta/categoria) e apaga. Toda mudança
# re-publica o documento daquela conversa no RAG (FaqPublisher é idempotente).
class AiAgent::Api::V1::Accounts::TrainingFaqsController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action -> { check_authorization(::AiAgent::TrainingConversation) }
  before_action :set_faq_location, only: [:update, :destroy]

  # Todas as FAQs publicadas do account, achatando as conversas.
  def index
    faqs = published_conversations.flat_map do |training|
      Array(training.faqs).each_with_index.map { |faq, index| serialize_faq(training, faq, index) }
    end
    mark_duplicates!(faqs)
    render json: { payload: faqs }
  end

  def update
    faqs = current_faqs
    return render_faq_not_found if faqs[@faq_index].nil?

    faqs[@faq_index] = faqs[@faq_index].merge(faq_params.to_h)
    ::AiAgent::Training::FaqPublisher.call(training: @training_conversation, faqs: faqs)
    render json: serialize_faq(@training_conversation, faqs[@faq_index], @faq_index)
  end

  def destroy
    faqs = current_faqs
    return render_faq_not_found if faqs[@faq_index].nil?

    faqs.delete_at(@faq_index)
    ::AiAgent::Training::FaqPublisher.call(training: @training_conversation, faqs: faqs)
    head :no_content
  end

  # Exclusão em massa. Sem `ids` → apaga TODAS (despublica cada conversa). Com
  # `ids` (lista de "<conversa>-<índice>") → apaga só os selecionados, agrupando
  # por conversa e re-publicando uma vez cada (os índices restantes reindexam).
  def destroy_all
    ids = Array(params[:ids])
    if ids.empty?
      destroy_every_faq
    else
      ids.group_by { |composite| composite.to_s.split('-', 2).first }
         .each { |training_id, composites| drop_faqs(training_id, composites) }
    end
    head :no_content
  end

  private

  def destroy_every_faq
    published_conversations.each { |training| ::AiAgent::Training::FaqPublisher.call(training: training, faqs: []) }
  end

  # Remove os índices `composites` ("<conversa>-<índice>") de uma conversa e
  # re-publica o restante (os índices seguintes reindexam naturalmente).
  def drop_faqs(training_id, composites)
    training = Current.account.ai_agent_training_conversations.find(training_id)
    drop = composites.to_set { |composite| composite.to_s.split('-', 2).last.to_i }
    faqs = Array(training.faqs).map(&:dup).reject.with_index { |_faq, i| drop.include?(i) }
    ::AiAgent::Training::FaqPublisher.call(training: training, faqs: faqs)
  end

  def published_conversations
    Current.account.ai_agent_training_conversations.where.not(published_at: nil).ordered
  end

  # Marca como duplicata cada FAQ cuja pergunta é semanticamente igual a outra
  # ANTERIOR na lista (perguntas equivalentes vindas de conversas diferentes).
  def mark_duplicates!(faqs)
    dups = AiAgent::Training::DuplicateScanner.within(faqs.pluck(:pergunta_paciente))
    faqs.each_with_index { |faq, i| faq[:duplicate] = dups.include?(i) }
  end

  # Resolve a conversa + o índice da FAQ a partir do id composto "<id>-<index>".
  def set_faq_location
    training_id, index = params[:id].to_s.split('-', 2)
    @training_conversation = Current.account.ai_agent_training_conversations.find(training_id)
    @faq_index = index.to_i
  end

  # Cópia rasa (dup de cada hash) pra não mutar o jsonb original antes de salvar.
  def current_faqs
    Array(@training_conversation.faqs).map(&:dup)
  end

  def faq_params
    params.require(:faq).permit(:pergunta_paciente, :resposta_clinica, :categoria)
  end

  def serialize_faq(training, faq, index)
    {
      id: "#{training.id}-#{index}",
      training_conversation_id: training.id,
      index: index,
      origem: training.name,
      pergunta_paciente: faq['pergunta_paciente'],
      resposta_clinica: faq['resposta_clinica'],
      categoria: faq['categoria']
    }
  end

  def render_faq_not_found
    render json: { error: 'FAQ não encontrada' }, status: :not_found
  end
end
