json.array! @agenda_events do |agenda_event|
  json.partial! 'api/v1/models/agenda_event', formats: [:json], resource: agenda_event
end
