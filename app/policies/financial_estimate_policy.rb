class FinancialEstimatePolicy < ApplicationPolicy
  def index?
    beclinic_can?(:financial, :view_estimates)
  end

  def show?
    beclinic_can?(:financial, :view_estimates)
  end

  def create?
    beclinic_can?(:financial, :create_estimate)
  end

  def update?
    beclinic_can?(:financial, :edit_estimate)
  end

  def destroy?
    beclinic_can?(:financial, :delete_estimate)
  end

  def approve?
    beclinic_can?(:financial, :approve_estimate)
  end

  def cancel?
    beclinic_can?(:financial, :edit_estimate)
  end

  def pay?
    beclinic_can?(:financial, :create_estimate)
  end

  def refund?
    beclinic_can?(:financial, :delete_estimate)
  end
end
