class Api::V1::Accounts::BeclinicPermissionsController < Api::V1::Accounts::BaseController
  # GET /api/v1/accounts/:account_id/beclinic_permissions
  # Returns the current user's RBAC permissions for this account.
  # Used by the frontend on boot to populate the permissions store.
  def show
    render json: {
      beclinic_role: current_user.beclinic_role_for(current_account),
      permissions: current_user.beclinic_permissions_for(current_account),
      klivy_role: current_klivy_role_data
    }, status: :ok
  end

  private

  def current_klivy_role_data
    role = current_user.klivy_role_for(current_account)
    return nil unless role

    { id: role.id, name: role.name, preset_key: role.preset_key }
  end
end
