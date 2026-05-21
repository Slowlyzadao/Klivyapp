json.array! @rules do |rule|
  json.partial! 'api/v1/models/agenda_notification_rule', resource: rule
end
