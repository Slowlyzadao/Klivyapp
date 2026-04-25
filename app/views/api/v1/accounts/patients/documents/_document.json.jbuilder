json.id document.id
json.account_id document.account_id
json.patient_id document.patient_id
json.form_template_id document.form_template_id
json.document_type document.document_type
json.status document.status
json.title document.title
json.version document.version
json.is_generated document.is_generated
json.file_name document.file_name
json.mime_type document.mime_type
json.file_size document.file_size
json.variables document.variables

json.sent_at document.sent_at
json.signed_at document.signed_at
json.created_at document.created_at
json.updated_at document.updated_at

json.url document.signed_url

json.generated_by do
  if document.generated_by
    json.id document.generated_by.id
    json.name document.generated_by.name
  else
    json.null!
  end
end

json.signed_by do
  if document.signed_by
    json.id document.signed_by.id
    json.name document.signed_by.name
  else
    json.null!
  end
end
