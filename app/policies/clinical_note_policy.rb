class ClinicalNotePolicy < ApplicationPolicy
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
    return false if record.status_signed?

    beclinic_can?(:patients, :create_clinical_notes)
  end

  def destroy?
    return false if record.status_signed?

    beclinic_can?(:patients, :delete_clinical_notes)
  end

  def sign?
    beclinic_can?(:patients, :sign_clinical_notes)
  end

  # Errata: só notas assinadas e ainda válidas; permissão alinhada à de assinar
  # (quem assina é responsável por flagar registros incorretos).
  def mark_erratum?
    return false unless record.status_signed?
    return false if record.erratum?

    beclinic_can?(:patients, :sign_clinical_notes)
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.where(account_id: account.id)
    end
  end
end
