class FinancialEstimatePolicy < ApplicationPolicy
  # Orçamentos no financeiro central são gateados pelas keys do catálogo:
  # `manage_estimates` (criar/editar/cancelar/excluir) e `approve_estimate`
  # (aprovar). Visualização passa com qualquer perm de view financeira.
  FINANCIAL_VIEW_PERMS = AccountTransactionPolicy::FINANCIAL_VIEW_PERMS

  def index?
    FINANCIAL_VIEW_PERMS.any? { |perm| beclinic_can?(:financial, perm) }
  end

  def show?
    index?
  end

  def create?
    beclinic_can?(:financial, :manage_estimates)
  end

  def update?
    beclinic_can?(:financial, :manage_estimates)
  end

  def destroy?
    beclinic_can?(:financial, :manage_estimates)
  end

  def approve?
    beclinic_can?(:financial, :approve_estimate)
  end

  def cancel?
    beclinic_can?(:financial, :manage_estimates)
  end

  def pay?
    beclinic_can?(:financial, :create_transaction)
  end

  def refund?
    beclinic_can?(:financial, :delete_transaction)
  end
end
