class PortalPolicy < ApplicationPolicy
  def index?
    @account.users.include?(@user)
  end

  def show?
    index?
  end

  def ssl_status?
    index?
  end

  def create?
    return true if @account_user.administrator?

    beclinic_can?(:help_center, :manage_portals)
  end

  def update?
    create?
  end

  def edit?
    create?
  end

  def destroy?
    create?
  end

  def logo?
    create?
  end

  def send_instructions?
    create?
  end
end

PortalPolicy.prepend_mod_with('PortalPolicy')
