json.partial! 'api/v1/accounts/patients/consent_records/consent_record', consent_record: @consent
json.signature_blob @consent.signature_blob

