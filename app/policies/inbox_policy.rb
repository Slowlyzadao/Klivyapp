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
      # Klivy Custom Roles: users with `settings.inboxes_view` see every
      # inbox in the account, mirroring the administrator scope. Without
      # this, an inbox created by a custom-role user disappears from their
      # list (they're not an InboxMember yet) and the next "create" attempt
      # fails with "phone number já está em uso".
      if account && user.respond_to?(:beclinic_can?) &&
         user.beclinic_can?(account, :settings, :inboxes_view)
        return account.inboxes
      end
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

  # Klivy Custom Roles fallback: every action is allowed for native admins
  # OR for users whose KlivyRole grants the matching `settings.inboxes_*`
  # permission. `beclinic_can?` already returns true for super admins and
  # admins natively, so the OR keeps backwards-compat.
  def campaigns?
    @account_user.administrator? || beclinic_can?(:settings, :inboxes_view)
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
    @account_user.administrator? || beclinic_can?(:settings, :inboxes_manage_agents)
  end

  def avatar?
    @account_user.administrator? || beclinic_can?(:settings, :inboxes_edit)
  end

  def sync_templates?
    @account_user.administrator? || beclinic_can?(:settings, :inboxes_edit)
  end

  def health?
    @account_user.administrator? || beclinic_can?(:settings, :inboxes_view)
  end
end
