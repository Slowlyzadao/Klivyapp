class CategoryPolicy < ApplicationPolicy
  def index?
    @account.users.include?(@user)
  end

  def show?
    return true if @account_user.administrator?

    beclinic_can?(:help_center, :manage_categories)
  end

  def create?
    show?
  end

  def update?
    show?
  end

  def edit?
    show?
  end

  def destroy?
    show?
  end
end

CategoryPolicy.prepend_mod_with('CategoryPolicy')
