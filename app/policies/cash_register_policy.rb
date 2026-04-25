class CashRegisterPolicy < ApplicationPolicy
  def index?   = beclinic_can?(:financial, :view_transactions)
  def show?    = beclinic_can?(:financial, :view_transactions)
  def create?  = beclinic_can?(:financial, :create_transaction)
  def update?  = beclinic_can?(:financial, :create_transaction)
  def destroy? = beclinic_can?(:financial, :delete_transaction)

  class Scope < Scope
    def resolve
      scope.where(account_id: account.id)
    end
  end
end
