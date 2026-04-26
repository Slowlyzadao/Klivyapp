class AgentBotPolicy < ApplicationPolicy
  def index?
    # leitura aberta a qualquer agente (usado em selects de inbox)
    @account_user.administrator? || @account_user.agent?
  end

  def show?
    index?
  end

  def create?
    return true if @account_user.administrator?

    beclinic_can?(:settings, :agent_bots_manage)
  end

  def update?
    create?
  end

  def destroy?
    create?
  end

  def avatar?
    create?
  end

  def reset_access_token?
    create?
  end
end
