class SlaPolicyPolicy < ApplicationPolicy
  def index?
    return true if @account_user.administrator?

    beclinic_can?(:settings, :sla_view)
  end

  def show?
    index?
  end

  def create?
    return true if @account_user.administrator?

    beclinic_can?(:settings, :sla_create)
  end

  def update?
    return true if @account_user.administrator?

    beclinic_can?(:settings, :sla_edit)
  end

  def destroy?
    return true if @account_user.administrator?

    beclinic_can?(:settings, :sla_delete)
  end
end
