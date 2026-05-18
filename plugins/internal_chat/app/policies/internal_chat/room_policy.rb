class InternalChat::RoomPolicy < ApplicationPolicy
  def index?
    true
  end

  def show?
    member? || @account_user.administrator?
  end

  def create?
    true # qualquer usuário autenticado pode iniciar conversa
  end

  def update?
    member_with_role?(%w[owner admin]) || @account_user.administrator?
  end

  def update_avatar?
    update?
  end

  def remove_avatar?
    update?
  end

  def destroy?
    @record.created_by_user_id == @user.id || @account_user.administrator?
  end

  def unread_summary?
    true
  end

  def archive?
    member_with_role?(%w[owner admin]) || @account_user.administrator?
  end

  def unarchive?
    archive?
  end

  def mute?
    member?
  end

  def unmute?
    member?
  end

  private

  def member?
    @record.memberships.where(user_id: @user.id, left_at: nil).exists?
  end

  def member_with_role?(roles)
    @record.memberships.where(user_id: @user.id, left_at: nil, role: roles).exists?
  end
end
