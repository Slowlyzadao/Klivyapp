class WebhookPolicy < ApplicationPolicy
  def index?
    return true if @account_user.administrator?

    beclinic_can?(:settings, :integrations_view)
  end

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
end
