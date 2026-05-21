class TreatmentItemPolicy < ApplicationPolicy
  def index?
    beclinic_can?(:patients, :view_treatment_plans)
  end

  def show?
    beclinic_can?(:patients, :view_treatment_plans)
  end

  def create?
    beclinic_can?(:patients, :manage_treatment_plans)
  end

  def update?
    beclinic_can?(:patients, :manage_treatment_plans)
  end

  def destroy?
    beclinic_can?(:patients, :manage_treatment_plans)
  end

  def approve?
    update?
  end

  def cancel?
    update?
  end
end
