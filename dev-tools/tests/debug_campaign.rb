campaign = Campaign.last
puts "Campaign ID: #{campaign.id}"
puts "Account ID: #{campaign.account_id}"
puts "Audience: #{campaign.audience.inspect}"

audience_label_ids = campaign.audience.select { |audience| audience['type'] == 'Label' }.pluck('id')
puts "Audience Label IDs: #{audience_label_ids.inspect}"

labels = campaign.account.labels.where(id: audience_label_ids)
puts "Found Labels: #{labels.pluck(:title).inspect}"

labels_titles = labels.pluck(:title)
contacts = campaign.account.contacts.tagged_with(labels_titles, any: true)
puts "Contacts count: #{contacts.count}"

conversations = campaign.account.conversations.tagged_with(labels_titles, any: true)
puts "Conversations count: #{conversations.count}"
conversations.each do |conv|
  puts "Conv Contact: #{conv.contact.inspect}"
end
