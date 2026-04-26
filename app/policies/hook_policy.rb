class HookPolicy < ApplicationPolicy
  def create?
    return true if @account_user.administrator?

    beclinic_can?(:settings, :integrations_manage)
  end

  def update?
    create?
  end

  def destroy?
    create?
  end

  def process_event?
    true
  end
end
