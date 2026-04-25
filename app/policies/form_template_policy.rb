class FormTemplatePolicy < ApplicationPolicy
  def index?
    account_user.present?
  end

  def show?
    account_user.present?
  end

  def create?
    administrator? || supervisor?
  end

  def update?
    administrator? || supervisor?
  end

  def destroy?
    administrator?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.for_account_or_global(account.id)
    end
  end

  private

  def administrator?
    account_user&.administrator?
  end

  def supervisor?
    account_user&.custom_role&.name == 'supervisor'
  end
end
