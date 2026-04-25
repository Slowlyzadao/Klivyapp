class AgendaNotificationLogPolicy < ApplicationPolicy
  # Todos os membros autenticados podem ver os logs
  def index?
    account_user?
  end

  # Sem criação/edição/exclusão manual — logs são gerados internamente
  private

  def account_user?
    @account_user.present?
  end
end
