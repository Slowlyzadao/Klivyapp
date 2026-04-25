class WaitingListEntryPolicy < ApplicationPolicy
  def index?
    beclinic_can?(:agenda, :view)
  end

  def create?
    beclinic_can?(:agenda, :create_event)
  end

  def update?
    beclinic_can?(:agenda, :create_event)
  end

  def destroy?
    beclinic_can?(:agenda, :create_event)
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.where(account_id: account.id)
    end
  end
end
