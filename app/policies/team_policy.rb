class TeamPolicy < ApplicationPolicy
  # Auditoria A-5: actions de mutação ganham fallback Klivy `beclinic_can?`.
  # Sem isso, role Klivy "Gerente" com `settings.teams_create=true` não
  # conseguia criar teams (backend negava). Admin nativo continua passando.
  def index?
    true
  end

  def update?
    @account_user.administrator? || beclinic_can?(:settings, :teams_edit)
  end

  def show?
    true
  end

  def create?
    @account_user.administrator? || beclinic_can?(:settings, :teams_create)
  end

  def destroy?
    @account_user.administrator? || beclinic_can?(:settings, :teams_delete)
  end
end
