class Api::V1::Accounts::FinancialGoalsController < Api::V1::Accounts::BaseController
  before_action :fetch_account
  after_action :verify_authorized

  def show
    authorize @account, policy_class: FinancialGoalPolicy
    render json: {
      monthly_goal: @account.monthly_goal.to_f,
      quarterly_goal: @account.quarterly_goal.to_f,
      annual_goal: @account.annual_goal.to_f
    }
  end

  def update
    authorize @account, policy_class: FinancialGoalPolicy
    if @account.update(goals_params)
      render json: {
        monthly_goal: @account.monthly_goal.to_f,
        quarterly_goal: @account.quarterly_goal.to_f,
        annual_goal: @account.annual_goal.to_f
      }
    else
      render json: { error: @account.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  def goals_params
    params.permit(:monthly_goal, :quarterly_goal, :annual_goal)
  end

  def fetch_account
    @account = Current.account
  end
end
