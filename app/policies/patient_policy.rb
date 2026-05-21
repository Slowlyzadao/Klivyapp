class PatientPolicy < ApplicationPolicy
  def index?
    beclinic_can?(:patients, :view)
  end

  def show?
    return false unless beclinic_can?(:patients, :view)
    return true if beclinic_scope(:patients) == 'all'

    # scope=own: só permite ver pacientes onde é o responsible_professional
    record.responsible_professional_id == user.id
  end

  def by_contact?
    beclinic_can?(:patients, :view)
  end

  def create?
    beclinic_can?(:patients, :create)
  end

  def update?
    beclinic_can?(:patients, :edit)
  end

  def destroy?
    beclinic_can?(:patients, :delete)
  end

  def restore?
    beclinic_can?(:patients, :create)
  end

  def archived?
    beclinic_can?(:patients, :view)
  end

  def summary?
    show?
  end

  def status?
    beclinic_can?(:patients, :edit)
  end

  def quick_action?
    beclinic_can?(:patients, :edit)
  end

  def audit_logs?
    beclinic_can?(:patients, :view_audit)
  end

  def timeline?
    beclinic_can?(:patients, :view_timeline)
  end

  def change_history?
    beclinic_can?(:patients, :view_audit)
  end

  def export?
    beclinic_can?(:patients, :view)
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      base = scope.where(account: account)
      return base if user.beclinic_scope(account, :patients) == 'all'

      # scope=own: filtra apenas pacientes do profissional responsável
      base.where(responsible_professional_id: user.id)
    end
  end
end
