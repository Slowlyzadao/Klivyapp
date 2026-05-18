json.conversations do
  json.array! @conversations do |conversation|
    json.id conversation.display_id
    json.account_id conversation.account_id
    json.inbox_id conversation.inbox_id
    json.last_activity_at conversation.last_activity_at&.to_i
    json.created_at conversation.created_at.to_i

    json.contact do
      contact = conversation.contact
      next unless contact

      json.id contact.id
      json.name contact.name
      json.phone_number contact.phone_number
      json.email contact.email
      json.thumbnail contact.avatar_url
    end

    json.inbox do
      inbox = conversation.inbox
      next unless inbox

      json.id inbox.id
      json.name inbox.name
      json.channel_type inbox.channel_type
    end

    last_message = conversation.messages.try(:last)
    json.last_message do
      next unless last_message

      json.id last_message.id
      json.content last_message.content
      json.created_at last_message.created_at.to_i
    end
  end
end

json.contacts do
  json.array! @contacts do |contact|
    json.id contact.id
    json.name contact.name
    json.phone_number contact.phone_number
    json.email contact.email
    json.identifier contact.identifier
    json.thumbnail contact.avatar_url
    json.last_activity_at contact.last_activity_at&.to_i
  end
end
