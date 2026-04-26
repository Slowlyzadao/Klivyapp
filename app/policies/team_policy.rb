class TeamPolicy < ApplicationPolicy
  def index?
    return true if @account_user.administrator?

    beclinic_can?(:settings, :teams_view)
  end

  def show?
    index?
  end

  def create?
    return true if @account_user.administrator?

    beclinic_can?(:settings, :teams_create)
  end

  def update?
    return true if @account_user.administrator?

    beclinic_can?(:settings, :teams_edit)
  end

  def destroy?
    return true if @account_user.administrator?

    beclinic_can?(:settings, :teams_delete)
  end
end
