json.payload do
  json.partial! 'api/v1/accounts/patients/anamneses/anamnesis', anamnesis: @anamnesis
end
