json.id exam_media.id
json.account_id exam_media.account_id
json.patient_id exam_media.patient_id
json.session_log_id exam_media.session_log_id
json.appointment_id exam_media.appointment_id
json.category exam_media.category
json.file_name exam_media.file_name
json.mime_type exam_media.mime_type
json.file_size exam_media.file_size
json.description exam_media.description
json.tags exam_media.tags
json.url exam_media.signed_url
json.created_at exam_media.created_at
json.updated_at exam_media.updated_at

json.uploaded_by do
  if exam_media.uploaded_by
    json.id exam_media.uploaded_by.id
    json.name exam_media.uploaded_by.name
  else
    json.null!
  end
end
