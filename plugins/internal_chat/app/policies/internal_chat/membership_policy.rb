# Gatea CRUD de memberships de salas do Chat Interno. Extraído do
# check inline `can_manage_group?` que vivia no MembershipsController
# (auditoria SEC-5, 2026-05-18).
#
# Comportamento atual (mantém compatibilidade total com pre-auditoria):
#   - Admin da conta: bypass.
#   - Membros da sala podem listar (index).
#   - Owner/Admin da sala (`role IN ('owner', 'admin')`) pode adicionar,
#     promover/rebaixar e remover membros — incluindo auto-saída de
#     qualquer membro.
#
# Extension point pra release futuro:
#   A perm granular `internal_chat:manage_memberships` foi adicionada ao
#   catálogo Klivy (não-bloqueante hoje). Quando o ciclo de role
#   granular for ativado, a policy passa a exigir essa perm além do papel
#   da sala — substituir o método `room_manager?` por algo como:
#
#     beclinic_can?(:internal_chat, :manage_memberships) &&
#       room_role_in?(%w[owner admin])
class InternalChat::MembershipPolicy < ApplicationPolicy
  def index?
    return true if @account_user.administrator?
    return false unless can_view_feature?

    member?
  end

  def create?
    return true if @account_user.administrator?
    return false unless can_view_feature?

    room_manager?
  end

  def update?
    create?
  end

  def destroy?
    # Auto-saída é sempre permitida (membro deixando o grupo).
    return true if leaving_self?

    create?
  end

  private

  def room
    @record.is_a?(InternalChat::Room) ? @record : @record.room
  end

  def can_view_feature?
    @account_user.administrator? || beclinic_can?(:internal_chat, :view)
  end

  # RT-2: scope `.active` (canon) em vez de hardcoded `left_at: nil`.
  def member?
    room.memberships.active.where(user_id: @user.id).exists?
  end

  def room_manager?
    room.memberships
        .active
        .where(user_id: @user.id, role: %w[owner admin])
        .exists?
  end

  def leaving_self?
    @record.is_a?(InternalChat::Membership) && @record.user_id == @user.id
  end
end
