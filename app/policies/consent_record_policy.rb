class ConsentRecordPolicy < ApplicationPolicy
  def index?
    beclinic_can?(:patients, :view_consents)
  end

  def show?
    beclinic_can?(:patients, :view_consents)
  end

  def create?
    beclinic_can?(:patients, :manage_consents)
  end

  def update?
    beclinic_can?(:patients, :manage_consents)
  end

  def destroy?
    beclinic_can?(:patients, :manage_consents)
  end

  def sign?
    beclinic_can?(:patients, :manage_consents)
  end

  def revoke?
    beclinic_can?(:patients, :manage_consents)
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.where(account_id: account.id)
    end
  end
end
