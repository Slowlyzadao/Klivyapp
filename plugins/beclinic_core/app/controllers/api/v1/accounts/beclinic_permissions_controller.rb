class Api::V1::Accounts::BeclinicPermissionsController < Api::V1::Accounts::BaseController
  # GET /api/v1/accounts/:account_id/beclinic_permissions
  # Returns the current user's RBAC permissions for this account.
  # Used by the frontend on boot to populate the permissions store.
  def show
    render json: {
      beclinic_role: current_user.beclinic_role_for(current_account),
      permissions: current_user.beclinic_permissions_for(current_account),
      team: current_team_data
    }, status: :ok
  end

  private

  def current_team_data
    team = current_user.beclinic_team_for(current_account)
    return nil unless team

    {
      id: team.id,
      name: team.name,
      beclinic_role: team.beclinic_role,
      is_preset: team.is_preset
    }
  end
end
