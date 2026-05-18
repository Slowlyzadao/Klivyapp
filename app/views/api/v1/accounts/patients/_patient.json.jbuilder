json.id         patient.id
json.name       patient.name
json.social_name patient.social_name
json.phone      patient.phone
json.email      patient.email
json.cpf        patient.cpf
json.rg         patient.rg
json.birthdate  patient.birthdate
json.age        patient.age
json.sex        patient.sex
json.marital_status patient.marital_status
json.patient_status patient.patient_status
json.avatar_url patient.resolved_avatar_url
json.no_show_count patient.no_show_count
json.needs_recall patient.needs_recall
json.recall_dismissed_at patient.recall_dismissed_at&.iso8601
json.pinned_note patient.pinned_note
json.notes       patient.notes
json.origin     patient.origin
json.unit       patient.unit
json.contact_id patient.contact_id
json.responsible_professional_id patient.responsible_professional_id

json.address patient.address
json.emergency_contact patient.emergency_contact
json.has_guardian patient.has_guardian
json.guardian patient.guardian
json.insurance  patient.insurance

json.created_at patient.created_at.iso8601
json.updated_at patient.updated_at.iso8601
json.deleted_at patient.deleted_at&.iso8601

# Última consulta — usa o hash pré-calculado no controller (sem N+1)
last_visit_at = @last_visits&.dig(patient.contact_id)
json.last_visit last_visit_at&.iso8601

# Alertas críticos ativos
json.critical_alerts patient.critical_alerts.active.ordered_by_severity do |alert|
  json.partial! 'api/v1/accounts/patients/critical_alerts/critical_alert', alert: alert
end
