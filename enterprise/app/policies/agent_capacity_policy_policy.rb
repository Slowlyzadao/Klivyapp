class AgentCapacityPolicyPolicy < ApplicationPolicy
  def index?
    return true if @account_user.administrator?

    beclinic_can?(:settings, :users_view)
  end

  def show?
    index?
  end

  def create?
    return true if @account_user.administrator?

    beclinic_can?(:settings, :users_edit)
  end

  def update?
    create?
  end

  def destroy?
    create?
  end
end
