class InternalChat::StickerPolicy < ApplicationPolicy
  def index?
    true
  end

  def create?
    true
  end

  def destroy?
    return true if @account_user.administrator?

    @record.created_by_user_id == @user.id && @record.kind != 'default'
  end

  def favorite?
    true
  end

  def unfavorite?
    true
  end
end
