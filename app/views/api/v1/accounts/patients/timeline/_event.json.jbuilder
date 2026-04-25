json.extract! event,
              :id,
              :event_type,
              :label,
              :actor_name,
              :reference_type,
              :reference_id,
              :metadata,
              :occurred_at,
              :created_at

if event.actor.present?
  json.actor do
    json.id   event.actor.id
    json.name event.actor.name
  end
else
  json.actor nil
end
