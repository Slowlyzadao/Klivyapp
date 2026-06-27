# Endpoint do tom de voz da Bea (projeto de estilo). Recurso singular por conta:
#   GET  ai_agent/style_profile           → perfil ATIVO + RASCUNHO
#   POST ai_agent/style_profile/generate  → dispara a geração (rascunho)
#
# A geração roda async (AiAgent::GenerateStyleProfileJob) destilando as
# conversas concluídas do Treinamento. O ATIVO (style_profile) só muda quando
# o usuário aprovar o rascunho (Fase 3) — aqui ele nunca é tocado.
class AiAgent::Api::V1::Accounts::StyleProfilesController < Api::V1::Accounts::BaseController
  before_action :authorize_request

  def show
    render json: serialize(setting)
  end

  # Grava os campos no perfil ATIVO. Dois usos no mesmo endpoint:
  #   - aprovar (`approve: true`): promove o rascunho revisado e o CONSOME.
  #   - toggle/edição do ativo (sem `approve`): NÃO toca no rascunho — senão
  #     ligar/desligar o tom apagaria um rascunho 'ready' ainda não revisado.
  def update
    attrs = { style_profile: build_active }
    attrs[:style_profile_draft] = {} if approve?
    setting.update!(attrs)
    render json: serialize(setting)
  end

  def generate
    # Debounce: se já há uma geração em andamento, NÃO re-enfileira (evita
    # empilhar jobs de IA por conta). Marca 'generating' preservando o rascunho
    # anterior (merge) pra a UI já refletir antes do job rodar.
    unless generating?
      setting.update!(style_profile_draft: setting.style_profile_draft.merge(
        'status' => 'generating', 'started_at' => Time.current.iso8601
      ))
      ::AiAgent::GenerateStyleProfileJob.perform_later(Current.account.id)
    end
    render json: serialize(setting), status: :accepted
  end

  private

  def authorize_request
    authorize(Current.account, policy_class: ::AiAgent::StyleProfilePolicy)
  end

  # Em andamento = status generating E iniciado há pouco. Um 'generating' velho
  # (worker morto antes do status terminal) é STALE → não bloqueia regerar.
  STALE_AFTER = 5.minutes

  def generating?
    draft = setting.style_profile_draft
    return false unless draft['status'] == 'generating'

    started = draft['started_at']
    return false if started.blank?

    Time.zone.parse(started.to_s) > STALE_AFTER.ago
  rescue ArgumentError, TypeError
    false
  end

  # find_or_create_by! (não create_or_find_by!): o model valida unicidade de
  # account_id — create_or_find_by! estouraria RecordInvalid quando o setting já
  # existe (caso comum). Mesma convenção do resto do plugin.
  def setting
    @setting ||= ::AiAgent::AccountSetting.find_or_create_by!(account_id: Current.account.id)
  end

  def serialize(setting)
    {
      active: setting.style_profile,
      draft: setting.style_profile_draft
    }
  end

  # Normaliza o que vira o perfil ATIVO (com tetos defensivos; o renderer ainda
  # corta/sanitiza no momento de injetar no prompt).
  def build_active
    p = update_params
    {
      'enabled' => ActiveModel::Type::Boolean.new.cast(p[:enabled]) || false,
      'summary' => p[:summary].to_s,
      'greeting' => p[:greeting].to_s,
      'closing' => p[:closing].to_s,
      'emojis' => Array(p[:emojis]).map(&:to_s).first(20),
      'expressions' => Array(p[:expressions]).map(&:to_s).first(20),
      'examples' => normalize_examples(p[:examples])
    }
  end

  def normalize_examples(examples)
    Array(examples).first(12).map { |e| { 'paciente' => e[:paciente].to_s, 'clinica' => e[:clinica].to_s } }
  end

  def update_params
    params.require(:style_profile).permit(
      :enabled, :summary, :greeting, :closing,
      emojis: [], expressions: [], examples: [:paciente, :clinica]
    )
  end

  # Só a aprovação consome o rascunho; o toggle de enabled não.
  def approve?
    ActiveModel::Type::Boolean.new.cast(params[:approve])
  end
end
