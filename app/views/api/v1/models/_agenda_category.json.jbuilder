json.id                 resource.id
json.name               resource.name
json.color              resource.color
json.position           resource.position
json.active             resource.active
json.account_id         resource.account_id
json.appointments_count resource.try(:appointments_count_attr) || resource.appointments_count
json.created_at         resource.created_at
json.updated_at         resource.updated_at
