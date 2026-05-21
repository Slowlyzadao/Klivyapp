class AgentBotPolicy < ApplicationPolicy
  # Auditoria A-5: actions de mutação ganham fallback Klivy `beclinic_can?`.
  # `index?`/`show?` continuam abertos pra qualquer agent (bots são listados
  # em telas de configuração de inbox por qualquer agente). Mutações exigem
  # `settings.agent_bots_manage`. Admin nativo continua passando.
  def index?
    @account_user.administrator? || @account_user.agent?
  end

  def update?
    @account_user.administrator? || beclinic_can?(:settings, :agent_bots_manage)
  end

  def show?
    @account_user.administrator? || @account_user.agent?
  end

  def create?
    @account_user.administrator? || beclinic_can?(:settings, :agent_bots_manage)
  end

  def destroy?
    @account_user.administrator? || beclinic_can?(:settings, :agent_bots_manage)
  end

  def avatar?
    @account_user.administrator? || beclinic_can?(:settings, :agent_bots_manage)
  end

  def reset_access_token?
    @account_user.administrator? || beclinic_can?(:settings, :agent_bots_manage)
  end
end
