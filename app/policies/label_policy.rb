class LabelPolicy < ApplicationPolicy
  # Auditoria A-5: actions de mutação ganham fallback Klivy `beclinic_can?`.
  # Sem isso, role Klivy "Gerente" com `settings.labels_create=true` não
  # conseguia criar labels (backend negava). Admin nativo continua passando.
  def index?
    @account_user.administrator? || @account_user.agent?
  end

  def update?
    @account_user.administrator? || beclinic_can?(:settings, :labels_edit)
  end

  def show?
    # Labels são listadas/usadas por todos os agents pra filtrar conversas.
    # Mantém aberto pra agent (era admin-only por engano em Chatwoot upstream).
    @account_user.administrator? || @account_user.agent?
  end

  def create?
    @account_user.administrator? || beclinic_can?(:settings, :labels_create)
  end

  def destroy?
    @account_user.administrator? || beclinic_can?(:settings, :labels_delete)
  end
end
