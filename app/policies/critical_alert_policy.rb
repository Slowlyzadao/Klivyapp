class CriticalAlertPolicy < ApplicationPolicy
  def index?
    account_user.present?
  end

  def show?
    account_user.present?
  end

  def create?
    # Apenas profissionais e admins podem criar alertas clínicos
    administrator? || supervisor? || professional?
  end

  def update?
    administrator? || supervisor? || professional?
  end

  def destroy?
    administrator? || supervisor?
  end

  def deactivate?
    administrator? || supervisor? || professional?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.where(account: account)
    end
  end

  private

  def administrator?
    account_user&.administrator?
  end

  def supervisor?
    account_user&.custom_role&.name == 'supervisor'
  end

  def professional?
    account_user&.role == 'agent'
  end
end
