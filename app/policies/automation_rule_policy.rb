class AutomationRulePolicy < ApplicationPolicy
  def index?
    return true if @account_user.administrator?

    beclinic_can?(:settings, :automation_view)
  end

  def show?
    index?
  end

  def create?
    return true if @account_user.administrator?

    beclinic_can?(:settings, :automation_create)
  end

  def update?
    return true if @account_user.administrator?

    beclinic_can?(:settings, :automation_edit)
  end

  def clone?
    create?
  end

  def destroy?
    return true if @account_user.administrator?

    beclinic_can?(:settings, :automation_delete)
  end
end
