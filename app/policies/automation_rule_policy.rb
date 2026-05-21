class AutomationRulePolicy < ApplicationPolicy
  # Auditoria A-5: actions ganham fallback Klivy `beclinic_can?`. Sem isso,
  # role Klivy "Gerente" com `settings.automation_view=true` não conseguia
  # listar automations (backend negava). Admin nativo continua passando.
  def index?
    @account_user.administrator? || beclinic_can?(:settings, :automation_view)
  end

  def create?
    @account_user.administrator? || beclinic_can?(:settings, :automation_create)
  end

  def show?
    @account_user.administrator? || beclinic_can?(:settings, :automation_view)
  end

  def update?
    @account_user.administrator? || beclinic_can?(:settings, :automation_edit)
  end

  def clone?
    # Clone é semanticamente uma criação a partir de outra regra.
    @account_user.administrator? || beclinic_can?(:settings, :automation_create)
  end

  def destroy?
    @account_user.administrator? || beclinic_can?(:settings, :automation_delete)
  end
end
