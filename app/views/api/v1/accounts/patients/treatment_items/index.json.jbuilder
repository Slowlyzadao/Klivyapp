json.data do
  json.array! @treatment_items do |treatment_item|
    json.partial! 'api/v1/accounts/patients/treatment_items/treatment_item', treatment_item: treatment_item
  end
end
