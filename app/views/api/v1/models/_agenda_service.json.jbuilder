json.id                   resource.id
json.name                 resource.name
json.duration_minutes     resource.duration_minutes
json.price                resource.price.to_f
json.requires_room        resource.requires_room
json.color                resource.color
json.position             resource.position
json.account_id           resource.account_id
json.default_category_id  resource.respond_to?(:default_category_id) ? resource.default_category_id : nil
json.created_at           resource.created_at
json.updated_at           resource.updated_at
