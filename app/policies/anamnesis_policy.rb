class AnamnesisPolicy < ApplicationPolicy
  def index?
    beclinic_can?(:patients, :view_clinical_notes)
  end

  def show?
    beclinic_can?(:patients, :view_clinical_notes)
  end

  def create?
    beclinic_can?(:patients, :create_clinical_notes)
  end

  def update?
    return false if record.is_a?(Anamnesis) && record.status_finalized?

    beclinic_can?(:patients, :create_clinical_notes)
  end

  def destroy?
    return false if record.is_a?(Anamnesis) && record.status_finalized?

    beclinic_can?(:patients, :delete_clinical_notes)
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.where(account_id: account.id)
    end
  end
end
