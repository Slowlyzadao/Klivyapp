class CannedResponsePolicy < ApplicationPolicy
  def index?
    # qualquer agente lista respostas (usado dentro do composer)
    @account_user.administrator? || @account_user.agent?
  end

  def show?
    index?
  end

  def create?
    return true if @account_user.administrator?

    beclinic_can?(:settings, :canned_create)
  end

  def update?
    return true if @account_user.administrator?

    beclinic_can?(:settings, :canned_edit)
  end

  def destroy?
    return true if @account_user.administrator?

    beclinic_can?(:settings, :canned_delete)
  end
end
