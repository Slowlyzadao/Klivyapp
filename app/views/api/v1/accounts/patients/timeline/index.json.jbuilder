json.events do
  json.array! @events do |event|
    json.partial! 'api/v1/accounts/patients/timeline/event', event: event
  end
end

json.meta do
  json.total_count @events.total_count
  json.page        @events.current_page
  json.per_page    @events.limit_value
  json.total_pages @events.total_pages
end
