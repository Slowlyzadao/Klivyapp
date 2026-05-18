class FinancialDashboardPolicy < ApplicationPolicy
  def show?
    @account_user&.administrator? || beclinic_can?(:financial, :view_dashboard)
  end
end
