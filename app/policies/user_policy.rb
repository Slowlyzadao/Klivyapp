class UserPolicy < ApplicationPolicy
  def index?
    return true if @account_user.administrator?

    beclinic_can?(:settings, :users_view)
  end

  def create?
    return true if @account_user.administrator?

    beclinic_can?(:settings, :users_invite)
  end

  def update?
    return true if @account_user.administrator?

    beclinic_can?(:settings, :users_edit)
  end

  def destroy?
    return true if @account_user.administrator?

    beclinic_can?(:settings, :users_remove)
  end

  def bulk_create?
    create?
  end
end
