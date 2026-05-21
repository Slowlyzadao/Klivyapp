class FinancialGoalPolicy < ApplicationPolicy
  def show?
    @account_user&.administrator? || beclinic_can?(:financial, :view_dashboard)
  end

  def update?
    @account_user&.administrator? || beclinic_can?(:financial, :manage_settings)
  end
end
