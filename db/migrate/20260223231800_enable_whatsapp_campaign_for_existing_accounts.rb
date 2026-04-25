# Enable whatsapp_campaign for existing accounts.
# The feature flag was previously set to enabled: false in features.yml,
# which prevented WhatsApp campaigns from being dispatched.
# This migration enables it for all existing accounts.
class EnableWhatsappCampaignForExistingAccounts < ActiveRecord::Migration[7.0]
  def up
    Account.find_in_batches(batch_size: 100) do |accounts|
      accounts.each { |account| account.enable_features!('whatsapp_campaign') }
    end
  end
end
