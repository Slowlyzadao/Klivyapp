class AccountTransactionPolicy < ApplicationPolicy
  def index?
    beclinic_can?(:financial, :view_transactions)
  end

  def show?
    beclinic_can?(:financial, :view_transactions)
  end

  def create?
    beclinic_can?(:financial, :create_transaction)
  end

  def update?
    beclinic_can?(:financial, :create_transaction)
  end

  def destroy?
    beclinic_can?(:financial, :delete_transaction)
  end
end
