class FinancialGoalPolicy < ApplicationPolicy
  # Meta financeira é exibida no Dashboard. Editar exige manage_settings.
  def show?
    beclinic_can?(:financial, :view_dashboard)
  end

  def update?
    beclinic_can?(:financial, :manage_settings)
  end
end
