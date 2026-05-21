json.payload do
  json.partial! 'api/v1/accounts/patients/patient', patient: @patient
end
