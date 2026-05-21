json.payload do
  json.array! @anamneses do |anamnesis|
    json.partial! 'api/v1/accounts/patients/anamneses/anamnesis', anamnesis: anamnesis
  end
end
