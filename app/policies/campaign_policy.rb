class CampaignPolicy < ApplicationPolicy
  # Visualização exige `campaigns.view`. Operações de escrita exigem o
  # `manage_*` específico do canal da inbox: Website → manage_live_chat,
  # SMS/Twilio SMS → manage_sms, Whatsapp → manage_whatsapp.
  # Quando o controller passa a classe Campaign (sem instância — caso do
  # create), aceita se o usuário tem qualquer manage_*.
  def index?
    return true if @account_user.administrator?

    beclinic_can?(:campaigns, :view) ||
      beclinic_can?(:campaigns, :manage_live_chat) ||
      beclinic_can?(:campaigns, :manage_sms) ||
      beclinic_can?(:campaigns, :manage_whatsapp)
  end

  def show?
    index?
  end

  def create?
    return true if @account_user.administrator?

    if record.is_a?(Class)
      beclinic_can?(:campaigns, :manage_live_chat) ||
        beclinic_can?(:campaigns, :manage_sms) ||
        beclinic_can?(:campaigns, :manage_whatsapp)
    else
      can_manage_campaign_channel?
    end
  end

  def update?
    return true if @account_user.administrator?

    can_manage_campaign_channel?
  end

  def destroy?
    update?
  end

  private

  def can_manage_campaign_channel?
    return false unless record.respond_to?(:inbox)

    case record.inbox&.inbox_type
    when 'Website'
      beclinic_can?(:campaigns, :manage_live_chat)
    when 'Sms', 'Twilio SMS'
      beclinic_can?(:campaigns, :manage_sms)
    when 'Whatsapp'
      beclinic_can?(:campaigns, :manage_whatsapp)
    else
      false
    end
  end
end
