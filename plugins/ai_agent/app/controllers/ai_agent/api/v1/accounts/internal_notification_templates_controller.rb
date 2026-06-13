# CRUD dos templates de notificação interna da Bea. UI vive em
# /accounts/:id/ai_agent/templates (rota Vue do plugin). Cada template
# é único por (account, event_key) — clínica edita o body, troca o
# destino (sala/DM) ou desativa.
#
# Endpoint extra `catalog` retorna o vocabulário pra UI montar o
# dropdown de eventos + lista de salas/users disponíveis como destino.
class AiAgent::Api::V1::Accounts::InternalNotificationTemplatesController < Api::V1::Accounts::BaseController
  before_action -> { check_authorization(AiAgent::InternalNotificationTemplate) }
  before_action :set_template, only: %i[show update destroy]

  def index
    templates = AiAgent::InternalNotificationTemplate
                .where(account_id: Current.account.id)
                .order(:event_key)
    render json: templates.map { |t| serialize(t) }
  end

  def show
    render json: serialize(@template)
  end

  # Cria um template caso a clínica adicione um event_key que ainda não
  # foi seedado (ex: novo evento adicionado em release futuro). Defaults
  # vêm do EventCatalog se não enviados no payload.
  def create
    event_key = params.dig(:internal_notification_template, :event_key) ||
                params[:event_key]
    return render(json: { errors: ['event_key inválido'] }, status: :unprocessable_entity) unless valid_event?(event_key)

    template = AiAgent::InternalNotificationTemplate.new(
      defaults_for(event_key).merge(template_params.to_h).merge(account_id: Current.account.id)
    )

    if template.save
      render json: serialize(template), status: :created
    else
      render json: { errors: template.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # UX-fix 2026-05-19: quando user clica "Ativar" no card e o template
  # está com `target_type='disabled'` (estado inicial após seed), antes
  # o PUT só atualizava `enabled=true` mas o Router continuava
  # bloqueando o dispatch porque `disabled?` checa AMBOS
  # `target_type != 'disabled'` E `enabled = true`. Resultado: usuário
  # clicava "Ativar" e nada acontecia em prod (notificação não saía,
  # card visualmente continuava inativo).
  #
  # Agora: se o caller pede `enabled: true` E o template está disabled
  # (sem destino), auto-promovemos pra `room` apontando pra recepção.
  # Toast no front explica. Se NÃO houver sala system_role='reception'
  # (raro — backfill do internal_chat cria), 422 com erro instrui o
  # front a abrir modal pra usuário escolher destino manualmente.
  def update
    payload = template_params.to_h

    if should_auto_promote?(payload)
      reception_id = reception_room_id
      if reception_id
        payload[:target_type] = 'room'
        payload[:target_id]   = reception_id
      else
        return render(json: {
          errors: ['Configure o destino antes de ativar — não há sala "Recepção" pra ativação automática.'],
          code: 'destination_required'
        }, status: :unprocessable_entity)
      end
    end

    if @template.update(payload)
      render json: serialize(@template)
    else
      render json: { errors: @template.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # Reseta UM template ao default do EventCatalog (body, name, target).
  # Útil quando a clínica fez edits e quer voltar ao padrão.
  def reset
    @template = scoped.find(params[:id])
    meta = AiAgent::InternalNotifier::EventCatalog.entry(@template.event_key)
    return render(json: { errors: ['event_key sem default no catálogo'] }, status: :unprocessable_entity) unless meta

    reception_id = ::InternalChat::Room.where(account_id: Current.account.id, system_role: 'reception').pick(:id)
    @template.update!(
      name: meta[:label],
      body: meta[:default_body].to_s.strip,
      target_type: 'room',
      target_id: reception_id,
      enabled: true
    )
    render json: serialize(@template)
  end

  def destroy
    @template.destroy
    head :no_content
  end

  # Vocabulário pra UI montar dropdowns:
  #   events: lista do EventCatalog (label, vars, status do detector)
  #   rooms:  salas do Chat Interno desta conta
  #   users:  AccountUsers ativos (pra DM)
  def catalog
    account_id = Current.account.id

    events = AiAgent::InternalNotifier::EventCatalog::EVENTS.map do |key, meta|
      {
        event_key: key,
        label: meta[:label],
        description: meta[:description],
        available_vars: meta[:available_vars],
        detector_status: meta[:detector_status],
        icon: meta[:icon],
        color: meta[:color],
        default_body: meta[:default_body].to_s.strip
      }
    end

    rooms = ::InternalChat::Room
            .where(account_id: account_id, archived_at: nil)
            .order(Arel.sql('system_role IS NULL, system_role, name'))
            .map { |r| { id: r.id, name: r.name || 'Conversa', system_role: r.system_role, kind: r.kind } }

    # UX 2026-05-19/20: inclui `avatar_url` + `role` no payload pro
    # UserPickerSelect renderizar com avatar real (Avatar do core cai
    # pra iniciais se nulo) + badge de função consistente com a tela
    # /agents (Especialista, Recepcionista, Administrador).
    #
    # Resolução de `role` segue a MESMA hierarquia de `getAgentRoleName`
    # em routes/dashboard/settings/agents/Index.vue:
    #   1. beclinic_super_admin → "Super Admin"
    #   2. role nativo Chatwoot 'administrator' → "Administrador"
    #   3. klivy_role.name (preset Klivy: Especialista, Recepcionista, etc)
    #   4. custom_role.name (custom_role do core Chatwoot)
    #   5. role nativo Chatwoot (agent) → "Agente"
    account_users_by_user_id = ::AccountUser
                               .where(account_id: account_id)
                               .includes(:klivy_role, :custom_role)
                               .index_by(&:user_id)

    users = ::User.joins(:account_users)
                  .where(account_users: { account_id: account_id })
                  .order(:name)
                  .map do |u|
      au = account_users_by_user_id[u.id]
      {
        id: u.id,
        name: u.available_name,
        avatar_url: u.respond_to?(:avatar_url) ? u.avatar_url : nil,
        role: resolve_role_label(u, au)
      }
    end

    render json: { events: events, rooms: rooms, users: users }
  end

  private

  def scoped
    AiAgent::InternalNotificationTemplate.where(account_id: Current.account.id)
  end

  def set_template
    @template = scoped.find(params[:id])
  end

  def template_params
    params.require(:internal_notification_template).permit(
      :event_key, :name, :body, :target_type, :target_id, :enabled
    )
  end

  # UX: o card só envia `{ enabled: true }` no toggle. Auto-promove pra
  # `room` (reception) APENAS nesse caso — não em updates parciais que
  # mexem em outros campos (preserva intenção do user).
  def should_auto_promote?(payload)
    return false unless ActiveModel::Type::Boolean.new.cast(payload[:enabled])
    return false unless @template.target_type == 'disabled'

    # Só auto-promove se o payload NÃO está mudando target explicitamente.
    payload[:target_type].blank? && payload[:target_id].blank?
  end

  def reception_room_id
    ::InternalChat::Room
      .where(account_id: Current.account.id, system_role: 'reception')
      .pick(:id)
  end

  # Mesma hierarquia de resolução do `getAgentRoleName` em
  # `routes/dashboard/settings/agents/Index.vue`. Mantém o badge do
  # UserPickerSelect consistente com a tela de Agentes.
  def resolve_role_label(user, account_user)
    return 'Super Admin' if user.respond_to?(:beclinic_super_admin) && user.beclinic_super_admin
    return 'Administrador' if account_user&.role == 'administrator'
    return account_user.klivy_role.name if account_user&.klivy_role&.name.present?
    return account_user.custom_role.name if account_user&.respond_to?(:custom_role) && account_user.custom_role&.name.present?

    # Fallback: role nativo Chatwoot (agent → "Agente").
    account_user&.role == 'agent' ? 'Agente' : nil
  end

  def valid_event?(event_key)
    AiAgent::InternalNotifier::EventCatalog.keys.include?(event_key)
  end

  def defaults_for(event_key)
    meta = AiAgent::InternalNotifier::EventCatalog.entry(event_key)
    reception_id = ::InternalChat::Room.where(account_id: Current.account.id, system_role: 'reception').pick(:id)
    {
      event_key: event_key,
      name: meta[:label],
      body: meta[:default_body].to_s.strip,
      target_type: 'room',
      target_id: reception_id,
      enabled: true
    }
  end

  def serialize(template)
    meta = AiAgent::InternalNotifier::EventCatalog.entry(template.event_key) || {}
    {
      id: template.id,
      event_key: template.event_key,
      event_label: meta[:label] || template.event_key,
      event_description: meta[:description],
      available_vars: meta[:available_vars] || [],
      detector_status: meta[:detector_status] || :planned,
      icon: meta[:icon],
      color: meta[:color],
      name: template.name,
      body: template.body,
      target_type: template.target_type,
      target_id: template.target_id,
      target_label: target_label(template),
      enabled: template.enabled,
      created_at: template.created_at,
      updated_at: template.updated_at
    }
  end

  def target_label(template)
    case template.target_type
    when 'room'
      room = ::InternalChat::Room.find_by(id: template.target_id)
      room ? "Sala: #{room.name}" : 'Sala removida'
    when 'user'
      user = ::User.find_by(id: template.target_id)
      user ? "DM: #{user.available_name}" : 'Usuário removido'
    else
      'Desativado'
    end
  end
end
