class AgendaSettingPolicy < ApplicationPolicy
  def show?
    account_user?
  end

  def update?
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
