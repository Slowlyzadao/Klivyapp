class Api::V1::Accounts::TeamsController < Api::V1::Accounts::BaseController
  before_action :fetch_team, only: [:show, :update, :destroy]
  before_action :check_authorization

  def index
    @teams = Current.account.teams
  end

  def show; end

  def create
    @team = Current.account.teams.new(team_params)
    @team.save!
  end

  def update
    @team.update!(team_params)
  end

  def destroy
    if @team.dono? && Current.account.teams.where(beclinic_role: 'dono').count <= 1
      return render json: { error: 'Não é possível remover o último perfil Dono da conta' }, status: :forbidden
    end

    @team.destroy!
    head :ok
  end

  private

  def fetch_team
    @team = Current.account.teams.find(params[:id])
  end

  def team_params
    # BeClinic sends `permissions` and `beclinic_role` directly. Since they are not columns 
    # of the teams table, Rails wrap_parameters ignores them. We fall back to `params` 
    # to avoid ParameterMissing errors and correctly permit these virtual attributes.
    base_params = params[:team].present? ? params.require(:team) : params
    base_params.permit(:name, :description, :allow_auto_assign, :beclinic_role, :is_preset, permissions: {})
  end
end
