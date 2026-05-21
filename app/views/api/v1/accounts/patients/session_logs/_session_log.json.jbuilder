json.extract! session_log,
              :id,
              :patient_id,
              :account_id,
              :treatment_plan_id,
              :treatment_item_id,
              :appointment_id,
              :form_template_id,
              :performed_at,
              :duration_minutes,
              :areas_treated,
              :products_used,
              :complications,
              :result_observed,
              :post_procedure_guidance,
              :return_needed,
              :return_in_days,
              :complaint_of_day,
              :assessment,
              :next_consultation_details,
              :observation,
              :status,
              :signed_at,
              :signed_by_id,
              :erratum_at,
              :erratum_by_id,
              :erratum_reason,
              :lock_version,
              :migrated_from_clinical_note_id,
              :patient_signed_at,
              :patient_signature_mode,
              :patient_signature_integrity_hash,
              :patient_signature_remote_link_sent_at,
              :patient_signature_remote_link_expires_at,
              :created_at,
              :updated_at

json.procedure_name       session_log.procedure_name.presence || session_log.treatment_item&.procedure_name
json.professional_id      session_log.professional_id
json.professional_name    session_log.professional&.name
# `avatar_url` cai pro Gravatar/placeholder do User quando não há foto custom.
# Usado pelo frontend pra renderizar avatar nos cards/tabela da Evolução.
json.professional_avatar_url session_log.professional&.avatar_url
json.treatment_plan_title session_log.treatment_plan&.title
json.within_draft_window  session_log.within_draft_window?
json.editable             session_log.respond_to?(:editable_by?) && session_log.editable_by?(current_user)
json.erratum              session_log.erratum?
json.patient_signed       session_log.patient_signed?
json.patient_signature_method session_log.patient_signature_method
json.patient_signature_image_url session_log.patient_signature_image_url

if session_log.signed_by
  json.signed_by do
    json.id   session_log.signed_by.id
    json.name session_log.signed_by.name
  end
end

if session_log.erratum_by
  json.erratum_by do
    json.id   session_log.erratum_by.id
    json.name session_log.erratum_by.name
  end
end
