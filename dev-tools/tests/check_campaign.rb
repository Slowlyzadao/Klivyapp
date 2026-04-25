
campaign = Campaign.last
puts "Campaign ID: #{campaign.id}"
puts "Status: #{campaign.campaign_status}"
puts "Scheduled At: #{campaign.scheduled_at}"
puts "Current Time: #{Time.current}"
puts "Account Feature Flag (:whatsapp_campaign): #{campaign.account.feature_enabled?(:whatsapp_campaign)}"
puts "Audience: #{campaign.audience}"
