json.id resource.id
json.title resource.title
json.description resource.description
json.starts_at resource.starts_at
json.ends_at resource.ends_at
json.status resource.status
json.event_type resource.event_type
json.custom_attributes resource.custom_attributes
json.user_id resource.user_id
json.contact_id resource.contact_id
json.account_id resource.account_id
json.created_at resource.created_at
json.updated_at resource.updated_at

if resource.contact.present?
  json.contact do
    json.id resource.contact.id
    json.name resource.contact.name
    json.phone_number resource.contact.phone_number
    json.email resource.contact.email
  end
end

if resource.user.present?
  json.user do
    json.id resource.user.id
    json.name resource.user.name
    json.email resource.user.email
  end
end
