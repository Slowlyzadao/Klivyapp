class CommissionRulePolicy < ApplicationPolicy
  # Regras de comissão são listadas em Relatórios e geridas em Configurações.
  def index?
    beclinic_can?(:financial, :view_reports) ||
      beclinic_can?(:financial, :manage_settings)
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
