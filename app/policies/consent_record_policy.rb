class ConsentRecordPolicy < ApplicationPolicy
  def index?
    beclinic_can?(:patients, :view_consents)
  end

  def show?
    beclinic_can?(:patients, :view_consents)
  end

  def create?
    beclinic_can?(:patients, :manage_consents)
  end

  def update?
    beclinic_can?(:patients, :manage_consents)
  end

  def destroy?
    beclinic_can?(:patients, :manage_consents)
  end

  def sign?
    beclinic_can?(:patients, :manage_consents)
  end

  def revoke?
    beclinic_can?(:patients, :manage_consents)
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      base = scope.where(account_id: account.id)
      return base if user.beclinic_scope(account, :patients) == 'all'

      # scope=own (auditoria A-6): consents só de pacientes onde o usuário é
      # `responsible_professional`. Mesma semântica do PatientPolicy::Scope —
      # garante que `policy_scope(ConsentRecord)` direto também respeite o
      # confinamento (defesa em profundidade; o entry point principal é o
      # `ConsentRecordsController#set_patient` que já usa `policy_scope(Patient)`).
      base.joins(:patient).where(patients: { responsible_professional_id: user.id })
    end
  end
end
