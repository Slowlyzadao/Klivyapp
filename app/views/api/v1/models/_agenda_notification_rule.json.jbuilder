json.id                   resource.id
json.title                resource.title
json.rule_type            resource.rule_type
json.icon                 resource.icon
# Frontend usa `iconColor` (camelCase) mas armazenamos como `icon_color` (snake_case)
json.iconColor            resource.icon_color
json.icon_color           resource.icon_color
json.trigger_offset_hours resource.trigger_offset_hours
# Frontend usa `message` — mapeamos de message_template
json.message              resource.message_template
json.message_template     resource.message_template
json.inboxes              resource.inboxes
json.enabled              resource.enabled
json.position             resource.position
json.account_id           resource.account_id
json.created_at           resource.created_at
json.updated_at           resource.updated_at
