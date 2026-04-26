class Api::V1::Accounts::KlivyRolesController < Api::V1::Accounts::BaseController
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
    role = Current.account.klivy_roles.new(role_params)
    role.save!
    render json: serialize(role), status: :created
  end

  def update
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
    account_user.update!(klivy_role_id: @role.id)
    render json: { user_id: account_user.user_id, klivy_role_id: @role.id }
  end

  private

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
