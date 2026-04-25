json.id consent_record.id
json.account_id consent_record.account_id
json.patient_id consent_record.patient_id
json.form_template_id consent_record.form_template_id
json.signature_image_url consent_record.signature_image_url
json.title consent_record.title
json.document_type consent_record.document_type
json.body consent_record.body
json.observations consent_record.observations
json.status consent_record.computed_status
json.mode consent_record.mode
json.ip_address consent_record.ip_address
json.signed_ip consent_record.ip_address
json.device_info consent_record.device_info
json.expires_after_days consent_record.expires_after_days
json.expires_at consent_record.expires_at
json.signed_at consent_record.signed_at
json.created_at consent_record.created_at
json.updated_at consent_record.updated_at
json.integrity_hash consent_record.integrity_hash

json.created_by do
  if consent_record.created_by
    json.id consent_record.created_by.id
    json.name consent_record.created_by.name
  else
    json.null!
  end
end
