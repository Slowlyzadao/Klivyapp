json.id resource.id
# could be nil for a deleted agent hence the safe operator before account id
json.account_id Current.account&.id
json.availability_status resource.availability_status
json.auto_offline resource.auto_offline
json.confirmed resource.confirmed?
json.email resource.email
json.provider resource.provider
json.available_name resource.available_name
json.custom_attributes resource.custom_attributes if resource.custom_attributes.present?
json.name resource.name
json.agenda_public_id resource.agenda_public_id
json.role resource.role
json.thumbnail resource.avatar_url
json.custom_role_id resource.current_account_user&.custom_role_id if ChatwootApp.enterprise?
json.klivy_role_id resource.current_account_user&.klivy_role_id
if resource.current_account_user&.klivy_role
  json.klivy_role do
    json.id resource.current_account_user.klivy_role.id
    json.name resource.current_account_user.klivy_role.name
    json.preset_key resource.current_account_user.klivy_role.preset_key
  end
end
json.beclinic_super_admin resource.beclinic_super_admin?
json.agenda_service_ids resource.respond_to?(:agenda_service_ids) ? resource.agenda_service_ids : []

