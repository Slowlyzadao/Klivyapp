json.logs @logs do |log|
  json.id         log.id
  json.sent_at    log.sent_at
  json.status     log.status
  json.error_message log.error_message

  json.rule do
    json.id       log.agenda_notification_rule&.id
    json.title    log.agenda_notification_rule&.title
    json.rule_type log.agenda_notification_rule&.rule_type
    json.icon     log.agenda_notification_rule&.icon
    json.icon_color log.agenda_notification_rule&.icon_color
  end

  json.event do
    json.id        log.agenda_event&.id
    json.title     log.agenda_event&.title
    json.starts_at log.agenda_event&.starts_at
  end
end

json.meta do
  json.total    @meta[:total]
  json.page     @meta[:page]
  json.per_page @meta[:per_page]
end
