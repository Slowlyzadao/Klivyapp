json.id             anamnesis.id
json.patient_id     anamnesis.patient_id
json.account_id     anamnesis.account_id
json.professional_id anamnesis.professional_id
json.form_template_id anamnesis.form_template_id
json.version_number anamnesis.version_number
json.specialty      anamnesis.specialty
json.status         anamnesis.status
json.finalized_at   anamnesis.finalized_at&.iso8601

# Campos clínicos
json.chief_complaint     anamnesis.chief_complaint
json.medical_history     anamnesis.medical_history     || {}
json.allergies           Array(anamnesis.allergies)
json.current_medications Array(anamnesis.current_medications)
json.surgical_history    anamnesis.surgical_history
json.family_history      anamnesis.family_history
json.pregnancy           anamnesis.pregnancy           || {}
json.relevant_habits     anamnesis.relevant_habits     || {}
json.contraindications   Array(anamnesis.contraindications)
json.additional_notes    anamnesis.additional_notes

json.created_at anamnesis.created_at.iso8601
json.updated_at anamnesis.updated_at.iso8601

if anamnesis.pdf.attached?
  json.pdf_url rails_blob_url(anamnesis.pdf, only_path: true)
else
  json.pdf_url nil
end
