# Gatea CRUD dos templates de notificação interna da Bea. Sem essa policy,
# qualquer membro da conta podia reescrever templates e redirecionar alertas
# pra DMs arbitrários (exfiltração + spam) — descoberto na auditoria SEC-2
# em 2026-05-18.
#
# Usa o módulo `captain` do catálogo Klivy: `view` para leitura/catálogo e
# `manage_templates` para mutações (create/update/destroy/reset). Ambas
# perms já existem em
# `plugins/custom_roles/app/models/klivy_role/permissions_catalog.rb`.
class AiAgent::InternalNotificationTemplatePolicy < ApplicationPolicy
  def index?
    @account_user.administrator? || beclinic_can?(:captain, :view)
  end

  def show?
    @account_user.administrator? || beclinic_can?(:captain, :view)
  end

  # Catalog é metadado pro UI (events + rooms + users) — gate de leitura
  # mesmo. Não expor sem auth porque revela lista de staff (vetor de phishing
  # interno: SEC-12 no audit).
  def catalog?
    @account_user.administrator? || beclinic_can?(:captain, :view)
  end

  def create?
    @account_user.administrator? || beclinic_can?(:captain, :manage_templates)
  end

  def update?
    @account_user.administrator? || beclinic_can?(:captain, :manage_templates)
  end

  def destroy?
    @account_user.administrator? || beclinic_can?(:captain, :manage_templates)
  end

  def reset?
    @account_user.administrator? || beclinic_can?(:captain, :manage_templates)
  end
end
