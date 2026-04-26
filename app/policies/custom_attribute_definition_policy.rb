class CustomAttributeDefinitionPolicy < ApplicationPolicy
  def index?
    # leitura aberta a qualquer agente (usado em formulários, conversas, etc)
    @account_user.administrator? || @account_user.agent?
  end

  def show?
    index?
  end

  def create?
    return true if @account_user.administrator?

    beclinic_can?(:settings, :custom_attributes_create)
  end

  def update?
    return true if @account_user.administrator?

    beclinic_can?(:settings, :custom_attributes_edit)
  end

  def destroy?
    return true if @account_user.administrator?

    beclinic_can?(:settings, :custom_attributes_delete)
  end
end
