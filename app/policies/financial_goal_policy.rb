class FinancialGoalPolicy < ApplicationPolicy
  def show?
    beclinic_can?(:financial, :view_transactions)
  end

  def update?
    beclinic_can?(:financial, :view_transactions)
  end
end
