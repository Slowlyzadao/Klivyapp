class Api::V1::Accounts::KlivyRolesController < Api::V1::Accounts::BaseController
  # Raised por `enforce_delegation_limit!` quando o requester (non-admin) tenta
  # delegar perms que ele próprio não tem. Renderiza 403 com a lista de keys
  # forbidden, ajudando o frontend a destacar exatamente o que foi rejeitado.
  class PrivilegeEscalationError < StandardError
    attr_reader :forbidden
    def initialize(forbidden)
      @forbidden = forbidden
      super("Cannot delegate permissions you do not have: #{forbidden.join(', ')}")
    end
  end

  rescue_from PrivilegeEscalationError do |e|
    render json: {
      error: 'forbidden_permission_escalation',
      message: 'Você não pode delegar permissões/escopos que você próprio não possui.',
      forbidden: e.forbidden
    }, status: :forbidden
  end

  before_action :authorize_action!
  before_action :fetch_role, only: [:show, :update, :destroy, :assign]

  def index
    roles = Current.account.klivy_roles.order(:name)
    render json: roles.map { |r| serialize(r) }
  end

  def show
    render json: serialize(@role)
  end

  def create
    # Sanitiza pra avaliar a forma canônica que será persistida (já com legacy
    # migrations expandidas). Sem isso, requester com `manage_users` legado
    # poderia tentar delegar `users_view/_edit/etc.` sem ter as keys novas.
    sanitized = KlivyRole::PermissionsCatalog.sanitize_and_migrate(role_params[:permissions] || {})
    enforce_delegation_limit!(sanitized)

    role = Current.account.klivy_roles.new(role_params)
    role.save!
    render json: serialize(role), status: :created
  end

  def update
    sanitized = KlivyRole::PermissionsCatalog.sanitize_and_migrate(role_params[:permissions] || {})
    enforce_delegation_limit!(sanitized)

    @role.update!(role_params)
    render json: serialize(@role)
  end

  def destroy
    AccountUser.where(klivy_role_id: @role.id).update_all(klivy_role_id: nil)
    @role.destroy!
    head :no_content
  end

  def assign
    user_id = params.require(:user_id)
    account_user = Current.account.account_users.find_by!(user_id: user_id)
    # Ao trocar de função, limpa o override per-user de `is_agenda_provider`
    # para que o novo papel ditado pelo preset volte a valer. Sem isso, um
    # usuário backfilled como `true` continuaria aparecendo na agenda mesmo
    # depois de virar Recepcionista/Gerente sem agenda.
    updates = { klivy_role_id: @role.id }
    updates[:is_agenda_provider] = nil if account_user.has_attribute?(:is_agenda_provider)
    account_user.update!(updates)
    render json: { user_id: account_user.user_id, klivy_role_id: @role.id }
  end

  private

  # Princípio: "não pode delegar perm que você próprio não tem" (auditoria
  # C-2 — defesa final contra privilege escalation). Para cada perm marcada
  # `true` no payload sanitizado, valida que o requester também a tem. Para
  # `scope`, bloqueia upgrade `own → all` (requester com scope=own não pode
  # delegar scope=all). Admins e SuperAdmins têm bypass total via
  # `beclinic_can?`/`beclinic_scope` que retornam true/'all' para eles.
  #
  # Quando há ao menos uma key forbidden, levanta `PrivilegeEscalationError`
  # que é renderizada como 403 pelo `rescue_from` no topo do controller.
  def enforce_delegation_limit!(requested_permissions)
    return if Current.account_user&.administrator?
    return if Current.user.respond_to?(:beclinic_super_admin?) && Current.user.beclinic_super_admin?
    return if requested_permissions.blank?

    forbidden = []

    requested_permissions.each do |mod_key, mod_perms|
      next unless mod_perms.is_a?(Hash)

      mod_perms.each do |perm_key, perm_value|
        if perm_key.to_s == 'scope'
          requested_scope = perm_value.to_s
          user_scope = Current.user.beclinic_scope(Current.account, mod_key.to_sym).to_s
          if user_scope == 'own' && requested_scope == 'all'
            forbidden << "#{mod_key}.scope=all"
          end
          next
        end

        next unless perm_value == true

        unless Current.user.beclinic_can?(Current.account, mod_key.to_sym, perm_key.to_sym)
          forbidden << "#{mod_key}.#{perm_key}"
        end
      end
    end

    raise PrivilegeEscalationError.new(forbidden) if forbidden.any?
  end

  def fetch_role
    @role = Current.account.klivy_roles.find(params[:id])
  end

  def role_params
    params.require(:klivy_role).permit(:name, :description, :preset_key, permissions: {})
  end

  # As funções personalizadas de uma conta são compartilhadas entre todos os
  # agentes — listar/visualizar é liberado para quem tem `settings.roles_view`
  # OU `settings.users_edit` (atribuir role a agente no editor de agente).
  # Mutations exigem a perm específica (create/edit/delete) ou ser admin.
  def authorize_action!
    return if Current.account_user&.administrator?

    permitted = case action_name.to_sym
                when :index, :show then beclinic_can_view_roles?
                when :create then beclinic_can?(:settings, :roles_create)
                when :update then beclinic_can?(:settings, :roles_edit)
                when :destroy then beclinic_can?(:settings, :roles_delete)
                when :assign then beclinic_can?(:settings, :users_edit)
                end

    render json: { error: 'forbidden' }, status: :forbidden unless permitted
  end

  def beclinic_can_view_roles?
    beclinic_can?(:settings, :roles_view) || beclinic_can?(:settings, :users_edit)
  end

  def beclinic_can?(mod, action)
    return false unless Current.user && Current.account

    Current.user.beclinic_can?(Current.account, mod, action)
  end

  def serialize(role)
    {
      id: role.id,
      name: role.name,
      description: role.description,
      preset_key: role.preset_key,
      permissions: role.permissions,
      member_count: AccountUser.where(klivy_role_id: role.id).count,
      created_at: role.created_at,
      updated_at: role.updated_at
    }
  end
end
