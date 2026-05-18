class Api::V1::Accounts::Captain::AssistantsController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action -> { check_authorization(Captain::Assistant) }

  before_action :set_assistant, only: [:show, :update, :destroy, :playground]

  def index
    @assistants = account_assistants.ordered
  end

  def show; end

  def create
    @assistant = account_assistants.create!(assistant_params)
  end

  def update
    @assistant.update!(assistant_params)
  end

  def destroy
    @assistant.destroy
    head :no_content
  end

  def playground
    response = Captain::Llm::AssistantChatService.new(assistant: @assistant).generate_response(
      additional_message: params[:message_content],
      message_history: message_history
    )

    render json: response
  rescue RubyLLM::ModelNotFoundError => e
    log_playground_error(e)
    render json: {
      error: true,
      message: I18n.t('captain.playground.errors.invalid_model',
                      default: 'O modelo de IA configurado não é reconhecido. Verifique a configuração em Settings → Captain.')
    }, status: :unprocessable_entity
  rescue RubyLLM::Error => e
    log_playground_error(e)
    render json: {
      error: true,
      message: I18n.t('captain.playground.errors.provider_error',
                      default: 'Não foi possível obter resposta do provedor de IA. Tente novamente em instantes.')
    }, status: :bad_gateway
  rescue StandardError => e
    log_playground_error(e)
    render json: {
      error: true,
      message: I18n.t('captain.playground.errors.unexpected',
                      default: 'Ocorreu um erro inesperado ao gerar a resposta da IA.')
    }, status: :internal_server_error
  end

  def tools
    assistant = Captain::Assistant.new(account: Current.account)
    @tools = assistant.available_agent_tools
  end

  private

  def set_assistant
    @assistant = account_assistants.find(params[:id])
  end

  def account_assistants
    @account_assistants ||= Captain::Assistant.for_account(Current.account.id)
  end

  def assistant_params
    permitted = params.require(:assistant).permit(:name, :description,
                                                  config: [
                                                    :product_name, :feature_faq, :feature_memory, :feature_citation,
                                                    :welcome_message, :handoff_message, :resolution_message,
                                                    :instructions, :temperature,
                                                    # Klivy / Bea-specific config fields. Without listing them here,
                                                    # Strong Parameters silently drops them and the user's toggle
                                                    # never reaches the DB.
                                                    :bea_enabled,
                                                    { clinic_profile: [:name, :address] }
                                                  ])

    # Handle array parameters separately to allow partial updates
    permitted[:response_guidelines] = params[:assistant][:response_guidelines] if params[:assistant].key?(:response_guidelines)

    permitted[:guardrails] = params[:assistant][:guardrails] if params[:assistant].key?(:guardrails)

    permitted
  end

  def playground_params
    params.require(:assistant).permit(:message_content, message_history: [:role, :content])
  end

  def message_history
    (playground_params[:message_history] || []).map { |message| { role: message[:role], content: message[:content] } }
  end

  def log_playground_error(error)
    Rails.logger.error(
      event: 'captain.playground.error',
      assistant_id: @assistant&.id,
      account_id: Current.account&.id,
      error_class: error.class.name,
      error_message: error.message
    )
  end
end
