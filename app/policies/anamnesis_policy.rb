class AnamnesisPolicy < ApplicationPolicy
  def index?
    administrator? || beclinic_can?(:patients, :view_anamnesis)
  end

  def show?
    administrator? || beclinic_can?(:patients, :view_anamnesis)
  end

  def create?
    administrator? || beclinic_can?(:patients, :manage_anamnesis)
  end

  def update?
    return false if record.is_a?(Anamnesis) && record.status_finalized?

    administrator? || beclinic_can?(:patients, :manage_anamnesis)
  end

  def destroy?
    return false if record.is_a?(Anamnesis) && record.status_finalized?

    administrator? || beclinic_can?(:patients, :manage_anamnesis)
  end

  private

  def administrator?
    @account_user&.administrator?
  end

  public

  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.where(account_id: account.id)
    end
  end
end
