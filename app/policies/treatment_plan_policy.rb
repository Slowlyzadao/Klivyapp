class TreatmentPlanPolicy < ApplicationPolicy
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
    return false if record.is_a?(TreatmentPlan) && !record.status_proposto?

    beclinic_can?(:patients, :manage_treatment_plans)
  end

  def destroy?
    return false if record.is_a?(TreatmentPlan) && !record.status_proposto?

    beclinic_can?(:patients, :manage_treatment_plans)
  end

  def approve?
    beclinic_can?(:patients, :manage_treatment_plans)
  end

  def cancel?
    beclinic_can?(:patients, :manage_treatment_plans)
  end
end
