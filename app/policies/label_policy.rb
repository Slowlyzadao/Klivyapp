class LabelPolicy < ApplicationPolicy
  def index?
    # qualquer agente lista labels (necessário pra filtrar conversas, etc)
    @account_user.administrator? || @account_user.agent?
  end

  def show?
    index?
  end

  def create?
    return true if @account_user.administrator?

    beclinic_can?(:settings, :labels_create)
  end

  def update?
    return true if @account_user.administrator?

    beclinic_can?(:settings, :labels_edit)
  end

  def destroy?
    return true if @account_user.administrator?

    beclinic_can?(:settings, :labels_delete)
  end
end
