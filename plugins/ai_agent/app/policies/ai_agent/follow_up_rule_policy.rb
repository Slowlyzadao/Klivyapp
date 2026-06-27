# Gatea CRUD das regras de follow-up da Bea. Sem essa policy, qualquer
# membro da conta podia criar/editar/deletar regras que disparam mensagens
# automáticas a pacientes (descoberto na auditoria SEC-1 — 2026-05-18).
#
# Usa o módulo `captain` do catálogo Klivy: `view` para leitura e
# `manage_follow_ups` para mutações. Ambas perms já existem em
# `plugins/custom_roles/app/models/klivy_role/permissions_catalog.rb`.
class AiAgent::FollowUpRulePolicy < ApplicationPolicy
  def index?
    @account_user.administrator? || beclinic_can?(:captain, :view)
  end

  def show?
    @account_user.administrator? || beclinic_can?(:captain, :view)
  end

  def create?
    @account_user.administrator? || beclinic_can?(:captain, :manage_follow_ups)
  end

  def update?
    @account_user.administrator? || beclinic_can?(:captain, :manage_follow_ups)
  end

  def destroy?
    @account_user.administrator? || beclinic_can?(:captain, :manage_follow_ups)
  end
end
