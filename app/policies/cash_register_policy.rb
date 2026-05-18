class CashRegisterPolicy < ApplicationPolicy
  def index?
    administrator? || beclinic_can?(:financial, :view_cash_register)
  end

  def show?
    administrator? || beclinic_can?(:financial, :view_cash_register)
  end

  def create?
    administrator? || beclinic_can?(:financial, :create_transaction)
  end

  def update?
    administrator? || beclinic_can?(:financial, :create_transaction)
  end

  def destroy?
    administrator? || beclinic_can?(:financial, :delete_transaction)
  end

  private

  def administrator?
    @account_user&.administrator?
  end

  class Scope < Scope
    def resolve
      scope.where(account_id: account.id)
    end
  end
end
