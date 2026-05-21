id = Campaign.last.audience.map {|a| a['id']}
labels = Campaign.last.account.labels.where(id: id).pluck(:title)
puts "Labels:"
puts labels
puts "Contacts count:"
puts Campaign.last.account.contacts.tagged_with(labels, any: true).count
puts "Conversations count:"
puts Campaign.last.account.conversations.tagged_with(labels, any: true).count
