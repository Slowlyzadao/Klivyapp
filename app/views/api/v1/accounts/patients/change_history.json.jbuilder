json.payload do
  json.array! @audit_logs do |log|
    json.id log.id
    json.action log.action
    json.actor do
      if log.actor.present?
        json.id log.actor.id
        json.name log.actor.name
      else
        json.name 'Sistema'
      end
    end
    json.changed_fields log.changed_fields
    json.resource_type log.resource_type
    json.old_value log.old_value
    json.new_value log.new_value
    json.ip_address log.ip_address
    json.occurred_at log.occurred_at
  end
end

json.meta do
  json.total_count @audit_logs.total_count
  json.current_page @audit_logs.current_page
  json.total_pages @audit_logs.total_pages
end
