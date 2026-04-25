json.id              note.id
json.patient_id      note.patient_id
json.account_id      note.account_id
json.professional_id note.professional_id
json.appointment_id  note.appointment_id
json.form_template_id note.form_template_id
json.note_date       note.note_date&.iso8601
json.status          note.status
json.signed_at       note.signed_at&.iso8601
json.signed_by_id    note.signed_by_id
json.within_draft_window note.within_draft_window?

# Corpo clínico
json.complaint_of_day    note.complaint_of_day
json.assessment          note.assessment
json.conduct             note.conduct
json.complications       note.complications
json.guidance_given      note.guidance_given
json.return_recommended  note.return_recommended&.iso8601

json.created_at note.created_at.iso8601
json.updated_at note.updated_at.iso8601

if note.professional.present?
  json.professional do
    json.id note.professional.id
    json.name note.professional.available_name
  end
end

if note.signed_by.present?
  json.signed_by do
    json.id note.signed_by.id
    json.name note.signed_by.available_name
  end
end
