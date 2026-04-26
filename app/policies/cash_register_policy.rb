class CashRegisterPolicy < ApplicationPolicy
  # Caixa diário: ver requer view_cash_register; abrir/fechar/lançar exige
  # create_transaction; excluir lançamento exige delete_transaction.
  def index?   = beclinic_can?(:financial, :view_cash_register)
  def show?    = index?
  def create?  = beclinic_can?(:financial, :create_transaction)
  def update?  = create?
  def destroy? = beclinic_can?(:financial, :delete_transaction)

  class Scope < Scope
    def resolve
      scope.where(account_id: account.id)
    end
  end
end
