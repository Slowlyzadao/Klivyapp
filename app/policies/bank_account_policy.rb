class BankAccountPolicy < ApplicationPolicy
  def index?
    beclinic_can?(:financial, :view_transactions)
  end

  def show?
    beclinic_can?(:financial, :view_transactions)
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

  private

  def administrator?
    @account_user&.administrator?
  end
end
