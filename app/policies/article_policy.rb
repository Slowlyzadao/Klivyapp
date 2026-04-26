class ArticlePolicy < ApplicationPolicy
  def index?
    @account.users.include?(@user)
  end

  def show?
    return true if @account_user.administrator?

    beclinic_can?(:help_center, :manage_articles)
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

  def reorder?
    show?
  end
end

ArticlePolicy.prepend_mod_with('ArticlePolicy')
