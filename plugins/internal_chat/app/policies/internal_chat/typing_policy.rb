# Gatea o broadcast de "digitando…" do Chat Interno. Extraído do check
# inline `authorize_room_access` do TypingController (auditoria SEC-4,
# 2026-05-18). Diferente do AttachmentPolicy, NÃO permite bypass do
# `administrator?` quando o admin não é membro — typing seria ruído pros
# outros membros (eles veem "Admin está digitando…" sem o admin estar na
# sala). Admin que quiser ver/escrever entra na sala primeiro.
class InternalChat::TypingPolicy < ApplicationPolicy
  def create?
    return false unless can_view_feature?

    member?
  end

  private

  def can_view_feature?
    @account_user.administrator? || beclinic_can?(:internal_chat, :view)
  end

  # RT-2: scope `.active` (canon) em vez de hardcoded `left_at: nil`.
  def member?
    @record.memberships.active.where(user_id: @user.id).exists?
  end
end
