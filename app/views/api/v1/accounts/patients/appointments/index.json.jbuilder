json.appointments do
  json.array! @appointments do |appointment|
    json.partial! 'api/v1/accounts/patients/appointments/appointment', appointment: appointment
  end
end

json.meta do
  json.total_count @appointments.total_count
  json.page        @appointments.current_page
  json.per_page    @appointments.limit_value
  json.total_pages @appointments.total_pages
end
