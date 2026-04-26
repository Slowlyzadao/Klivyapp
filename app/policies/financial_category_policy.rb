class FinancialCategoryPolicy < ApplicationPolicy
  # Categorias são consumidas por todos os modais financeiros (qualquer perm
  # de view basta) e geridas em Configurações.
  def index?
    AccountTransactionPolicy::FINANCIAL_VIEW_PERMS.any? { |perm| beclinic_can?(:financial, perm) }
  end

  def show?
    index?
  end

  def create?
    beclinic_can?(:financial, :manage_settings)
  end

  def update?
    create?
  end

  def destroy?
    create?
  end
end
