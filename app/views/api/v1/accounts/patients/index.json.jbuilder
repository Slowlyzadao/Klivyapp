json.payload do
  json.array! @patients do |patient|
    json.partial! 'api/v1/accounts/patients/patient', patient: patient
  end
end

json.meta do
  json.total_count @patients.total_count
  json.current_page @patients.current_page
  json.total_pages @patients.total_pages
end
