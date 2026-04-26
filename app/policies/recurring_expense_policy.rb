class RecurringExpensePolicy < ApplicationPolicy
  # Despesas recorrentes aparecem em "A Pagar" e em Configurações.
  def index?
    beclinic_can?(:financial, :view_payables) ||
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
