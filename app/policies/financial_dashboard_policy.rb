class FinancialDashboardPolicy < ApplicationPolicy
  def show?
    beclinic_can?(:financial, :view_transactions)
  end
end
