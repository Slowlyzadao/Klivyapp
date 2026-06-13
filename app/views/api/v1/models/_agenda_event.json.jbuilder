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
json.category_id resource.category_id
json.agenda_service_id resource.agenda_service_id
json.account_id resource.account_id
json.created_at resource.created_at
json.updated_at resource.updated_at

if resource.category.present?
  json.category do
    json.id resource.category.id
    json.name resource.category.name
    json.color resource.category.color
  end
end

# Snapshot inline do serviço — fonte da verdade para o frontend renderizar
# cor/nome do serviço sem depender do lookup por NAME (PR #6 da auditoria
# 2026-05-13). Quando o serviço foi soft-deletado (`deleted_at` presente),
# o frontend pode mostrar badge "Serviço arquivado".
if resource.agenda_service.present?
  json.agenda_service do
    json.id resource.agenda_service.id
    json.name resource.agenda_service.name
    json.color resource.agenda_service.color
    json.duration_minutes resource.agenda_service.duration_minutes
    # Preço removido em 2026-05-22 — agora vive em Financial::ServicePricing.
    json.deleted_at resource.agenda_service.deleted_at
  end
end

if resource.contact.present?
  json.contact do
    json.id resource.contact.id
    json.name resource.contact.name
    json.phone_number resource.contact.phone_number
    json.email resource.contact.email
    # Foto: prioriza o avatar do `Patient` (foto de perfil clínica),
    # cai pro `Contact.avatar_url` (avatar do Chatwoot) se não tiver.
    patient_avatar = resource.contact.respond_to?(:patient) ? resource.contact.patient&.resolved_avatar_url : nil
    json.avatar_url(patient_avatar.presence || resource.contact.avatar_url)
  end
end

if resource.user.present?
  json.user do
    json.id resource.user.id
    json.name resource.user.name
    json.email resource.user.email
    json.thumbnail resource.user.avatar_url
  end
end
