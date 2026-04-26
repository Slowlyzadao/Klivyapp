class AnamnesisPolicy < ApplicationPolicy
  def index?
    beclinic_can?(:patients, :view_anamnesis)
  end

  def show?
    beclinic_can?(:patients, :view_anamnesis)
  end

  def create?
    beclinic_can?(:patients, :manage_anamnesis)
  end

  def update?
    return false if record.is_a?(Anamnesis) && record.status_finalized?

    beclinic_can?(:patients, :manage_anamnesis)
  end

  def finalize?
    return false if record.is_a?(Anamnesis) && record.status_finalized?

    beclinic_can?(:patients, :manage_anamnesis)
  end

  def destroy?
    return false if record.is_a?(Anamnesis) && record.status_finalized?

    beclinic_can?(:patients, :manage_anamnesis)
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.where(account_id: account.id)
    end
  end
end
