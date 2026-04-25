class AgendaCustomAttributePolicy < ApplicationPolicy
  def index?
    account_user?
  end

  def show?
    account_user?
  end

  def create?
    administrator?
  end

  def update?
    administrator?
  end

  def destroy?
    administrator?
  end

  def reorder?
    administrator?
  end

  private

  def account_user?
    @account_user.present?
  end

  def administrator?
    @account_user&.administrator?
  end
end
