class AccountSamlSettingsPolicy < ApplicationPolicy
  def show?
    return true if @account_user.administrator?

    beclinic_can?(:settings, :security_view)
  end

  def create?
    return true if @account_user.administrator?

    beclinic_can?(:settings, :security_manage)
  end

  def update?
    create?
  end

  def destroy?
    create?
  end
end
