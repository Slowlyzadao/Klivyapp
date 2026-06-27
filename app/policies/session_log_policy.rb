class SessionLogPolicy < ApplicationPolicy
  # NOTE: este policy é chamado em DOIS contextos:
  #   1. `before_action :check_authorization` no Patients::BaseController, que
  #      passa a CLASSE `SessionLog` como `record` antes do controller resolver
  #      a action. Nesse caso, checks de instância (status_signed?, erratum?)
  #      seriam falsos por engano. Os helpers `record_signed?` / `record_erratum?`
  #      retornam false quando record não é instance.
  #   2. `authorize @session_log` dentro da action, com a instância já carregada.

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
    return false if record_signed?

    beclinic_can?(:patients, :create_clinical_notes)
  end

  def destroy?
    return false if record_signed?

    beclinic_can?(:patients, :delete_clinical_notes)
  end

  def sign?
    beclinic_can?(:patients, :sign_clinical_notes)
  end

  def mark_erratum?
    return false unless beclinic_can?(:patients, :sign_clinical_notes)

    # Quando record é CLASSE (before_action), permite passar — a action
    # validará a instância depois. Quando é instância, valida estado canônico.
    return true unless record_is_instance?

    record.status_signed? && !record.erratum?
  end

  def sign_patient_locally?
    return false unless beclinic_can?(:patients, :create_clinical_notes)
    return true unless record_is_instance?

    !record.patient_signed?
  end

  def send_patient_remote_signature_link?
    sign_patient_locally?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.where(account_id: account.id)
    end
  end

  private

  def record_is_instance?
    record.is_a?(SessionLog)
  end

  def record_signed?
    record_is_instance? && record.status_signed?
  end

  def record_erratum?
    record_is_instance? && record.erratum?
  end
end
