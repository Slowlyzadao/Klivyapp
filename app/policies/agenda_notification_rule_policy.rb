class AgendaNotificationRulePolicy < ApplicationPolicy
  # Qualquer membro autenticado da conta pode listar
  def index?
    account_user?
  end

  def show?
    account_user?
  end

  # Somente administradores criam, editam e deletam regras
  def create?
    administrator?
  end

  def update?
    administrator?
  end

  def destroy?
    administrator?
  end

  def toggle?
    administrator?
  end

  private

  def account_user?
    @account_user.present?
  end

  def administrator?
    @account_user&.administrator?
  end
end
