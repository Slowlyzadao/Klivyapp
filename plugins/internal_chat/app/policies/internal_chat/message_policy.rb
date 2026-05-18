class InternalChat::MessagePolicy < ApplicationPolicy
  def index?
    member?
  end

  def create?
    member?
  end

  def update?
    own_message? || @account_user.administrator?
  end

  def destroy?
    own_message? || @account_user.administrator?
  end

  private

  def member?
    return false if @record.respond_to?(:room) && @record.room.nil?

    room = @record.is_a?(InternalChat::Message) ? @record.room : @record
    room.memberships.where(user_id: @user.id, left_at: nil).exists?
  end

  def own_message?
    @record.is_a?(InternalChat::Message) && @record.sender_user_id == @user.id
  end
end
