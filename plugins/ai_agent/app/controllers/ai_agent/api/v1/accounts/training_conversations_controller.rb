# CRUD da aba "Treinamento" da Bea. O usuário sobe um .zip de conversa do
# WhatsApp (com o nome do remetente que é a CLÍNICA), que é enfileirado em
# AiAgent::ProcessTrainingConversationJob para virar FAQs. O conteúdo bruto
# é descartado ao final do job — aqui ficam só metadados e o resultado
# parseado (com PII já mascarada), exposto no `show` para revisão.
class AiAgent::Api::V1::Accounts::TrainingConversationsController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action -> { check_authorization(::AiAgent::TrainingConversation) }
  before_action :set_training_conversations, except: [:create]
  before_action :set_training_conversation, only: [:show, :destroy, :publish, :select_clinic]

  RESULTS_PER_PAGE = 25

  def index
    page = (params[:page] || 1).to_i
    scope = @training_conversations.where(archived_at: nil)
    count = scope.count
    paginated = scope.offset((page - 1) * RESULTS_PER_PAGE).limit(RESULTS_PER_PAGE)

    render json: {
      payload: paginated.map { |training| serialize_summary(training) },
      meta: { total_count: count, page: page }
    }
  end

  def show
    render json: serialize_detail(@training_conversation)
  end

  def create
    training = ::AiAgent::TrainingConversation.new(
      account: Current.account,
      name: resolved_name,
      clinic_sender_name: training_params[:clinic_sender_name]
    )
    training.zip_file.attach(training_params[:zip_file]) if training_params[:zip_file].present?

    if training.save
      ::AiAgent::ProcessTrainingConversationJob.perform_later(training.id)
      render json: serialize_summary(training), status: :created
    else
      render_could_not_create_error(training.errors.full_messages.join(', '))
    end
  end

  # mode 'conversation' apenas arquiva (some da lista, FAQs preservadas no RAG);
  # qualquer outro valor remove TUDO — inclusive as FAQs do RAG da Bea
  # (FaqPublisher com lista vazia despublica e limpa os chunks).
  def destroy
    if params[:mode] == 'conversation'
      @training_conversation.update!(archived_at: Time.current)
    else
      ::AiAgent::Training::FaqPublisher.call(training: @training_conversation, faqs: [])
      @training_conversation.destroy!
    end
    head :no_content
  end

  # Todas as FAQs sugeridas ainda NÃO publicadas (conversas completed sem
  # published_at), achatadas de todas as conversas — pra revisar/aprovar de uma
  # vez. Cada FAQ vem com `duplicate` (semântico): igual a outra do próprio lote
  # OU a uma já publicada — por padrão essas vêm desmarcadas na UI.
  def pending_faqs
    pending = @training_conversations.where(status: :completed, published_at: nil, archived_at: nil)
    faqs = pending.flat_map do |training|
      Array(training.faqs).each_with_index.map { |faq, index| pending_faq_json(training, faq, index) }
    end
    mark_pending_duplicates!(faqs)
    render json: { payload: faqs }
  end

  # Aprova em massa as FAQs selecionadas (ids "<conversa>-<índice>"), agrupando
  # por conversa e publicando cada uma uma vez no RAG da Bea.
  def approve_all
    Array(params[:ids]).group_by { |composite| composite.to_s.split('-', 2).first }
                       .each { |training_id, composites| publish_selected(training_id, composites) }
    head :no_content
  end

  # Exclusão em massa de TODAS as conversas visíveis (não arquivadas) — mesma
  # semântica do destroy individual: mode 'conversation' só arquiva (mantém as
  # FAQs no RAG); qualquer outro valor remove tudo, despublicando as FAQs.
  def destroy_all
    scope = @training_conversations.where(archived_at: nil)
    if params[:mode] == 'conversation'
      scope.update_all(archived_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    else
      scope.find_each { |training| ::AiAgent::Training::FaqPublisher.call(training: training, faqs: []) }
      scope.destroy_all
    end
    head :no_content
  end

  # Aprova as FAQs mantidas pelo usuário e publica no RAG da Bea.
  def publish
    faqs = (publish_params[:faqs] || []).map(&:to_h)
    document = ::AiAgent::Training::FaqPublisher.call(training: @training_conversation, faqs: faqs)
    return render_could_not_create_error('Nenhuma FAQ para publicar') if document.nil?

    render json: serialize_detail(@training_conversation)
  end

  # Usuário escolheu qual participante é a clínica → roda o pipeline completo.
  # Já marca :pending no clique pra o card sair da seleção na hora e o polling
  # do front assumir (o job roda async e muda pra extracting/completed).
  def select_clinic
    @training_conversation.update!(
      clinic_sender_name: select_clinic_params[:clinic_sender_name],
      status: :pending
    )
    ::AiAgent::ProcessTrainingConversationJob.perform_later(@training_conversation.id)
    render json: serialize_summary(@training_conversation)
  end

  # Seleção em massa: aplica a MESMA clínica a todas as conversas em
  # awaiting_clinic que tenham esse participante (o front auto-detecta pelo nome
  # mais repetido entre as conversas). As que não têm esse participante ficam
  # pra seleção manual. Cada uma volta pra :pending e reprocessa.
  def select_clinic_bulk
    name = params[:clinic_sender_name].to_s
    return render_could_not_create_error('Nome da clínica ausente') if name.blank?

    applied = 0
    @training_conversations.where(status: :awaiting_clinic).find_each do |training|
      next unless Array(training.participants).any? { |participant| participant['name'] == name }

      training.update!(clinic_sender_name: name, status: :pending)
      ::AiAgent::ProcessTrainingConversationJob.perform_later(training.id)
      applied += 1
    end
    render json: { applied: applied }
  end

  private

  def set_training_conversations
    @training_conversations = Current.account.ai_agent_training_conversations.ordered
  end

  def set_training_conversation
    @training_conversation = @training_conversations.find(params[:id])
  end

  def training_params
    params.require(:training_conversation).permit(:name, :clinic_sender_name, :zip_file)
  end

  def publish_params
    params.require(:training_conversation).permit(
      faqs: [:pergunta_paciente, :resposta_clinica, :categoria, :fonte]
    )
  end

  def select_clinic_params
    params.require(:training_conversation).permit(:clinic_sender_name)
  end

  # Sem nome explícito, usa o nome do arquivo .zip enviado.
  def resolved_name
    return training_params[:name] if training_params[:name].present?
    return training_params[:zip_file].original_filename.sub(/\.zip\z/i, '') if training_params[:zip_file].present?

    'Conversa do WhatsApp'
  end

  # Resumo para a listagem (sem o conteúdo parseado, que pode ser grande).
  def serialize_summary(training)
    {
      id: training.id,
      name: training.name,
      clinic_sender_name: training.clinic_sender_name,
      status: training.status,
      error_message: training.error_message,
      message_count: training.message_count,
      clinic_message_count: training.clinic_message_count,
      patient_message_count: training.patient_message_count,
      audio_total: training.audio_total,
      audio_transcribed: training.audio_transcribed,
      faq_count: training.faq_count,
      created_at: training.created_at.to_i,
      processed_at: training.processed_at&.to_i,
      published_at: training.published_at&.to_i,
      participants: training.participants
    }
  end

  # Detalhe inclui as mensagens parseadas e as FAQs geradas, para revisão. Cada
  # FAQ vem com `duplicate` — true quando a pergunta é SEMANTICAMENTE equivalente
  # a uma já publicada em outra conversa (evita respostas conflitantes na Bea).
  def serialize_detail(training)
    faqs = training.faqs
    dups = AiAgent::Training::DuplicateScanner.against(
      faqs.pluck('pergunta_paciente'),
      published_questions(training)
    )
    serialize_summary(training).merge(
      parsed_messages: training.parsed_messages,
      faqs: faqs.each_with_index.map { |faq, i| faq.merge('duplicate' => dups.include?(i)) }
    )
  end

  # Perguntas já publicadas nas OUTRAS conversas do account.
  def published_questions(training)
    Current.account.ai_agent_training_conversations
           .where.not(published_at: nil).where.not(id: training.id)
           .pluck(:faqs).flatten
           .filter_map { |faq| faq['pergunta_paciente'] if faq.is_a?(Hash) }
  end

  # Perguntas já publicadas em qualquer conversa do account.
  def all_published_questions
    Current.account.ai_agent_training_conversations
           .where.not(published_at: nil)
           .pluck(:faqs).flatten
           .filter_map { |faq| faq['pergunta_paciente'] if faq.is_a?(Hash) }
  end

  def pending_faq_json(training, faq, index)
    {
      id: "#{training.id}-#{index}",
      training_conversation_id: training.id,
      index: index,
      origem: training.name,
      pergunta_paciente: faq['pergunta_paciente'],
      resposta_clinica: faq['resposta_clinica'],
      categoria: faq['categoria'],
      fonte: faq['fonte']
    }
  end

  # Marca como duplicata cada FAQ pendente semanticamente igual a outra do lote
  # (uma ocorrência anterior) OU a uma já publicada — pra vir desmarcada na UI.
  def mark_pending_duplicates!(faqs)
    questions = faqs.pluck(:pergunta_paciente)
    within = AiAgent::Training::DuplicateScanner.within(questions)
    against = AiAgent::Training::DuplicateScanner.against(questions, all_published_questions)
    faqs.each_with_index { |faq, i| faq[:duplicate] = within.include?(i) || against.include?(i) }
  end

  # Publica só as FAQs selecionadas de uma conversa (índices de `composites`).
  def publish_selected(training_id, composites)
    training = @training_conversations.find(training_id)
    keep = composites.to_set { |composite| composite.to_s.split('-', 2).last.to_i }
    faqs = Array(training.faqs).each_with_index.select { |_faq, i| keep.include?(i) }.map(&:first)
    return if faqs.empty?

    ::AiAgent::Training::FaqPublisher.call(training: training, faqs: faqs)
  end
end
