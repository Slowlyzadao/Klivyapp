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
# Detalhes internos de role (IDs, preset_key, super_admin flag) são expostos
# apenas para admins ou usuários com `settings.users_view`. Telas que precisam
# apenas do nome legível do papel (badge do profissional responsável no
# prontuário, AuditLog, etc.) continuam recebendo `klivy_role.name`.
viewer_can_see_role_internals = Current.account_user&.administrator? ||
                                (Current.user.respond_to?(:beclinic_can?) &&
                                 Current.user.beclinic_can?(Current.account, :settings, :users_view))

if viewer_can_see_role_internals
  json.custom_role_id resource.current_account_user&.custom_role_id if ChatwootApp.enterprise?
  json.klivy_role_id resource.current_account_user&.klivy_role_id
  json.beclinic_super_admin resource.beclinic_super_admin?
end

if resource.current_account_user&.klivy_role
  json.klivy_role do
    json.name resource.current_account_user.klivy_role.name
    if viewer_can_see_role_internals
      json.id resource.current_account_user.klivy_role.id
      json.preset_key resource.current_account_user.klivy_role.preset_key
    end
  end
end

au = resource.current_account_user
# Quando a coluna `is_agenda_provider` ainda não existe no banco
# (migration não rodou), default = true para preservar o comportamento
# atual — todos os agentes seguem aparecendo na agenda. Após a migration,
# `agenda_provider?` resolve override → role default → false.
if au&.has_attribute?(:is_agenda_provider)
  json.is_agenda_provider au.agenda_provider?
  json.is_agenda_provider_override au.is_agenda_provider
else
  json.is_agenda_provider true
end

