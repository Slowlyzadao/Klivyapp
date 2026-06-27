# Endpoint do system message (system prompt) da Bea POR CONTA. Recurso singular:
#   GET   ai_agent/system_prompt → texto da conta + default do super admin
#   PATCH ai_agent/system_prompt → grava o texto da conta
#
# A conta segue 100% o `content` salvo aqui (congelado). Vazio = herda o default
# global do super admin em runtime (PromptBuilder). O botão "Restaurar padrão" da
# UI usa o `default` devolvido aqui (cliente preenche o textarea e salva) — por
# isso não há endpoint de reset: o usuário revisa antes de gravar.
class AiAgent::Api::V1::Accounts::SystemPromptsController < Api::V1::Accounts::BaseController
  before_action :authorize_request

  def show
    render json: serialize(setting)
  end

  def update
    # `.presence`: texto em branco/só-espaços vira nil (conta volta a herdar o
    # default em runtime), e a serialização (content/using_default) fica
    # consistente com o ConfigResolver, que também usa `.presence`. Texto real
    # é gravado verbatim.
    setting.update!(system_prompt: update_params[:content].presence)
    render json: serialize(setting)
  end

  private

  def authorize_request
    authorize(Current.account, policy_class: ::AiAgent::SystemPromptPolicy)
  end

  # find_or_create_by! (não create_or_find_by!): o model valida unicidade de
  # account_id — mesma convenção do StyleProfilesController.
  def setting
    @setting ||= ::AiAgent::AccountSetting.find_or_create_by!(account_id: Current.account.id)
  end

  def resolver
    @resolver ||= ::AiAgent::ConfigResolver.new(Current.account)
  end

  def serialize(setting)
    {
      content: setting.system_prompt.to_s,
      default: resolver.default_system_prompt,
      using_default: setting.system_prompt.blank?
    }
  end

  def update_params
    params.require(:system_prompt).permit(:content)
  end
end
