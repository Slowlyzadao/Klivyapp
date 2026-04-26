class CustomRolePolicy < ApplicationPolicy
  def index?
    return true if @account_user.administrator?

    beclinic_can?(:settings, :roles_view)
  end

  def show?
    index?
  end

  def create?
    return true if @account_user.administrator?

    beclinic_can?(:settings, :roles_create)
  end

  def update?
    return true if @account_user.administrator?

    beclinic_can?(:settings, :roles_edit)
  end

  def destroy?
    return true if @account_user.administrator?

    beclinic_can?(:settings, :roles_delete)
  end
end
