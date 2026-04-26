class FinancialDashboardPolicy < ApplicationPolicy
  def show?
    beclinic_can?(:financial, :view_dashboard)
  end
end
