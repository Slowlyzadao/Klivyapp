class ApplicationPolicy
  attr_reader :user_context, :user, :record, :account, :account_user

  def initialize(user_context, record)
    @user_context = user_context
    @user = user_context[:user]
    @account = user_context[:account]
    @account_user = user_context[:account_user]
    @record = record
  end

  def index?
    false
  end

  def show?
    scope.exists?(id: record.id)
  end

  def create?
    false
  end

  def new?
    create?
  end

  def update?
    false
  end

  def edit?
    update?
  end

  def destroy?
    false
  end

  def scope
    Pundit.policy_scope!(user_context, record.class)
  end

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
      scope
    end
  end

  private

  # Delegates to the BeclinicPermissible concern on User.
  # Super admins and dono-role users always return true.
  # Users with no team get no permissions (returns false).
  def beclinic_can?(module_name, action)
    user.beclinic_can?(account, module_name, action)
  end

  # Returns 'all' or 'own' scope for a module.
  def beclinic_scope(module_name)
    user.beclinic_scope(account, module_name)
  end
end
