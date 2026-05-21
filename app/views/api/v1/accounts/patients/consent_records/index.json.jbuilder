json.data do
  json.array! @consents do |consent|
    json.partial! 'api/v1/accounts/patients/consent_records/consent_record', consent_record: consent
  end
end
