json.payload do
  json.array! @notes do |note|
    json.partial! 'api/v1/accounts/patients/clinical_notes/clinical_note', note: note
  end
end
