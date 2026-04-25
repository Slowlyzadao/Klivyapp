class TransactionPolicy < ApplicationPolicy
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

  def approve?
    beclinic_can?(:financial, :view_cashflow)
  end

  def cancel?
    beclinic_can?(:financial, :create_transaction)
  end

  def pay?
    beclinic_can?(:financial, :create_transaction)
  end

  def refund?
    beclinic_can?(:financial, :delete_transaction)
  end

  def financial_summary?
    beclinic_can?(:financial, :view_transactions)
  end
end
