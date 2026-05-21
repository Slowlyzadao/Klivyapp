class InboxPolicy < ApplicationPolicy
  class Scope
    attr_reader :user_context, :user, :scope, :account, :account_user

    def initialize(user_context, scope)
      @user_context = user_context
      @user = user_context[:user]
      @account = user_context[:account]
      @account_user = user_context[:account_user]
      @scope = scope
    end

    def resolve
      return account.inboxes if account_user&.administrator?
      return account.inboxes if user.respond_to?(:beclinic_can?) &&
                                user.beclinic_can?(account, :settings, :inboxes_view)

      user.assigned_inboxes
    end
  end

  def index?
    true
  end

  def show?
    # FIXME: for agent bots, lets bring this validation to policies as well in future
    return true if @user.is_a?(AgentBot)

    Current.user.assigned_inboxes.include? record
  end

  def assignable_agents?
    true
  end

  def agent_bot?
    true
  end

  def campaigns?
    @account_user.administrator? || beclinic_can?(:settings, :inboxes_edit)
  end

  def create?
    @account_user.administrator? || beclinic_can?(:settings, :inboxes_create)
  end

  def update?
    @account_user.administrator? || beclinic_can?(:settings, :inboxes_edit)
  end

  def destroy?
    @account_user.administrator? || beclinic_can?(:settings, :inboxes_delete)
  end

  def set_agent_bot?
    @account_user.administrator? || beclinic_can?(:settings, :inboxes_edit)
  end

  def avatar?
    @account_user.administrator? || beclinic_can?(:settings, :inboxes_edit)
  end

  def sync_templates?
    @account_user.administrator? || beclinic_can?(:settings, :inboxes_edit)
  end

  def health?
    @account_user.administrator? || beclinic_can?(:settings, :inboxes_edit)
  end
end
