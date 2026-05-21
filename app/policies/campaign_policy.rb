class CampaignPolicy < ApplicationPolicy
  CHANNEL_PERM_MAP = {
    'Website' => :manage_live_chat,
    'Sms' => :manage_sms,
    'Twilio SMS' => :manage_sms,
    'Whatsapp' => :manage_whatsapp
  }.freeze

  def index?
    administrator? || beclinic_can?(:campaigns, :view)
  end

  def show?
    administrator? || beclinic_can?(:campaigns, :view)
  end

  def update?
    administrator? || channel_manage_permitted?
  end

  def create?
    administrator? || channel_manage_permitted?
  end

  def destroy?
    administrator? || channel_manage_permitted?
  end

  private

  def administrator?
    @account_user&.administrator?
  end

  # When `record` is a Campaign instance, check the channel-specific perm.
  # When `record` is the Campaign class (no instance — happens on Pundit's
  # `authorize Campaign` for new), accept any of the three manage perms.
  def channel_manage_permitted?
    return any_manage_permission? unless record.is_a?(Campaign) && record.inbox

    perm = CHANNEL_PERM_MAP[record.inbox.inbox_type]
    return false unless perm

    beclinic_can?(:campaigns, perm)
  end

  def any_manage_permission?
    CHANNEL_PERM_MAP.values.uniq.any? { |perm| beclinic_can?(:campaigns, perm) }
  end
end
