class RecurringExpensePolicy < ApplicationPolicy
  def index?
    administrator? ||
      beclinic_can?(:financial, :view_payables) ||
      beclinic_can?(:financial, :manage_settings)
  end

  def show?
    administrator? ||
      beclinic_can?(:financial, :view_payables) ||
      beclinic_can?(:financial, :manage_settings)
  end

  def create?
    administrator? || beclinic_can?(:financial, :manage_settings)
  end

  def update?
    administrator? || beclinic_can?(:financial, :manage_settings)
  end

  def destroy?
    administrator? || beclinic_can?(:financial, :manage_settings)
  end

  private

  def administrator?
    @account_user&.administrator?
  end
end
