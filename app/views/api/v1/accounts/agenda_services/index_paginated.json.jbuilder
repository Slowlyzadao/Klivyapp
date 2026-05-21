json.services @services do |service|
  json.id service.id
  json.name service.name
  json.color service.color
  json.duration_minutes service.duration_minutes
  json.price service.price
  json.requires_room service.requires_room
  json.position service.position
  json.account_id service.account_id
  json.created_at service.created_at
  json.updated_at service.updated_at
  # Colunas virtuais do PR de UI overhaul (2026-05-14): vêm de subqueries
  # COUNT no select. `.to_i` garante numeric em vez de string, que é como
  # alguns adapters PG retornam aliases de subquery.
  json.agenda_events_count service.agenda_events_count.to_i
  json.treatment_items_count service.treatment_items_count.to_i
end

json.meta do
  json.current_page @meta[:current_page]
  json.per_page @meta[:per_page]
  json.total_count @meta[:total_count]
  json.total_pages @meta[:total_pages]
end
