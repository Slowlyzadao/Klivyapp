# Gateamento das rooms do Chat Interno.
#
# Duas camadas de autorização:
#
#   1. **Feature gate (Klivy)**: usuário precisa de `internal_chat.view` pra
#      acessar a feature inteira. Sem isso, nenhuma rota responde — mesmo
#      que ele já seja membro de uma sala criada antes da role ser ajustada.
#
#   2. **Per-room gate (membership/ownership)**: dentro da feature liberada,
#      ações específicas dependem de ser membro com role suficiente:
#      - show/mute/unmute: precisa ser membro
#      - update/archive: membro com role owner ou admin
#      - destroy: criador da sala
#
# Admin sempre faz bypass das duas camadas.
class InternalChat::RoomPolicy < ApplicationPolicy
  def index?
    can_view_feature?
  end

  def show?
    return true if @account_user.administrator?
    return false unless can_view_feature?

    member?
  end

  def create?
    @account_user.administrator? || beclinic_can?(:internal_chat, :create_room)
  end

  def update?
    return true if @account_user.administrator?
    return false unless can_view_feature?

    member_with_role?(%w[owner admin])
  end

  def update_avatar?
    update?
  end

  def remove_avatar?
    update?
  end

  def destroy?
    return true if @account_user.administrator?
    return false unless can_view_feature?

    @record.created_by_user_id == @user.id
  end

  def unread_summary?
    can_view_feature?
  end

  # Arquivar é por-usuário (cada membro arquiva a própria visão), então
  # qualquer membro pode — igual a mute. Antes exigia owner/admin, o que
  # dava 403 garantido em DM (ambos os membros têm role 'member').
  def archive?
    return true if @account_user.administrator?
    return false unless can_view_feature?

    member?
  end

  def unarchive?
    archive?
  end

  def mute?
    return true if @account_user.administrator?
    return false unless can_view_feature?

    member?
  end

  def unmute?
    mute?
  end

  private

  def can_view_feature?
    @account_user.administrator? || beclinic_can?(:internal_chat, :view)
  end

  # RT-2: scope `.active` (canon) em vez de hardcoded `left_at: nil`.
  def member?
    @record.memberships.active.where(user_id: @user.id).exists?
  end

  def member_with_role?(roles)
    @record.memberships.active.where(user_id: @user.id, role: roles).exists?
  end
end
