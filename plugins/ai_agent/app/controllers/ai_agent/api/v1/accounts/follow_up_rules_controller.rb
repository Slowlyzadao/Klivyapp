# CRUD das regras de follow-up. Cada regra é por conta. A clínica
# gerencia pela página `/accounts/:id/ai_agent/follow_ups` (rota
# Vue do plugin). Não tem nada de Captain — é UI nova totalmente
# nossa em cima do plugin ai_agent.
class AiAgent::Api::V1::Accounts::FollowUpRulesController < Api::V1::Accounts::BaseController
  before_action -> { check_authorization(::AiAgent::FollowUpRule) }
  before_action :set_rule, only: %i[show update destroy]

  def index
    rules = ::AiAgent::FollowUpRule
            .where(account_id: Current.account.id)
            .ordered
    render json: rules.map { |r| serialize(r) }
  end

  def show
    render json: serialize(@rule)
  end

  def create
    rule = ::AiAgent::FollowUpRule.new(rule_params.merge(account_id: Current.account.id))
    assign_steps(rule, steps_param)
    if rule.save
      render json: serialize(rule), status: :created
    else
      render json: { errors: rule.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    ::AiAgent::FollowUpRule.transaction do
      @rule.assign_attributes(rule_params)
      assign_steps(@rule, steps_param)
      @rule.save!
    end
    # Descarta da memória os passos destruídos via autosave — senão o
    # serialize devolveria registros já apagados.
    @rule.steps.reload
    render json: serialize(@rule)
  rescue ActiveRecord::RecordInvalid
    render json: { errors: @rule.errors.full_messages }, status: :unprocessable_entity
  end

  def destroy
    @rule.destroy
    head :no_content
  end

  private

  def set_rule
    @rule = ::AiAgent::FollowUpRule.where(account_id: Current.account.id).find(params[:id])
  end

  def rule_params
    params.require(:follow_up_rule).permit(
      :name, :enabled, :position, :trigger_type, :offset_hours, :offset_unit,
      :context_brief, :max_per_target, :cooldown_minutes, :applies_to, :action_type, :static_body,
      :persona_override, :stop_on_reply, :stop_on_booking,
      :agenda_service_id, :recall_interval_value, :recall_interval_unit,
      :cloud_template_name, :cloud_template_lang,
      status_filter: {},
      cloud_template_params: []
    )
  end

  # Passos ADICIONAIS da cadência (2..N). O passo 1 são os campos flat
  # (offset_*/context_brief) acima. Retorna nil quando a chave `steps`
  # nem veio no payload (não mexe na cadência); array vazio limpa todos
  # os passos extras.
  def steps_param
    raw = params.require(:follow_up_rule)[:steps]
    return nil if raw.nil?

    Array(raw)
      .select { |s| s.respond_to?(:permit) } # ignora itens malformados (escalar) → 422, não 500
      .map { |s| s.permit(:offset_hours, :offset_unit, :context_brief, :static_body).to_h.symbolize_keys }
  end

  # Sincroniza os passos extras IN-PLACE por posição (o frontend continua
  # mandando a lista desejada inteira, sem rastrear ids): atualiza os
  # existentes, cria os que faltam e marca os excedentes pra destruição
  # (efetivada no save! da regra via autosave). NÃO usa destroy_all:
  # recriar os passos trocaria os step_id a cada save — execuções
  # pendentes perderiam o passo (cairiam no conteúdo do passo 1) e a
  # idempotência/cap chaveadas em step_id abririam janela de duplicação.
  # `position` começa em 1 (o passo 1 é a regra, posição 0).
  def assign_steps(rule, steps)
    return if steps.nil?

    # `rule.steps.to_a` (NÃO .ordered.to_a, que dispararia query nova com
    # instâncias destacadas): o autosave só persiste mudanças feitas nas
    # instâncias do próprio target da associação. O scope default já ordena.
    existing = rule.persisted? ? rule.steps.to_a : []
    steps.each_with_index do |s, idx|
      step = existing[idx] || rule.steps.build
      step.assign_attributes(
        position: idx + 1,
        offset_hours: s[:offset_hours].to_i,
        offset_unit: s[:offset_unit],
        context_brief: s[:context_brief],
        static_body: s[:static_body]
      )
    end
    existing[steps.length..].to_a.each(&:mark_for_destruction)
  end

  def serialize(rule)
    {
      id: rule.id, name: rule.name, enabled: rule.enabled, position: rule.position,
      trigger_type: rule.trigger_type, offset_hours: rule.offset_hours,
      offset_unit: rule.offset_unit, offset_seconds: rule.offset_seconds,
      applies_to: rule.applies_to, status_filter: rule.status_filter,
      max_per_target: rule.max_per_target, cooldown_minutes: rule.cooldown_minutes,
      steps: rule.steps.map { |s| serialize_step(s) },
      created_at: rule.created_at, updated_at: rule.updated_at
    }.merge(serialize_behavior(rule))
  end

  # Campos de comportamento/conteúdo (Fases 2–6) — separado pra manter
  # cada método dentro do limite de complexidade.
  def serialize_behavior(rule)
    {
      action_type: rule.action_type, context_brief: rule.context_brief,
      static_body: rule.static_body, persona_override: rule.persona_override,
      stop_on_reply: rule.stop_on_reply, stop_on_booking: rule.stop_on_booking,
      agenda_service_id: rule.agenda_service_id,
      recall_interval_value: rule.recall_interval_value, recall_interval_unit: rule.recall_interval_unit,
      cloud_template_name: rule.cloud_template_name, cloud_template_lang: rule.cloud_template_lang,
      cloud_template_params: rule.cloud_template_params
    }
  end

  def serialize_step(step)
    {
      id: step.id,
      position: step.position,
      offset_hours: step.offset_hours,
      offset_unit: step.offset_unit,
      offset_seconds: step.offset_seconds,
      context_brief: step.context_brief,
      static_body: step.static_body
    }
  end
end
