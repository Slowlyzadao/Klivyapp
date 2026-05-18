json.array! @categories do |category|
  json.partial! 'api/v1/models/agenda_category', resource: category
end
