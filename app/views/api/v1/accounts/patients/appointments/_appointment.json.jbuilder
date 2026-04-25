json.extract! appointment,
              :id,
              :appointment_type,
              :status,
              :scheduled_at,
              :ends_at,
              :duration_minutes,
              :cancellation_reason,
              :reschedule_reason,
              :notes,
              :recall_sent,
              :recall_sent_at,
              :return_in_days,
              :session_log_id,
              :treatment_plan_id,
              :agenda_event_id,
              :created_at,
              :updated_at

# Professional
json.professional do
  if appointment.professional.present?
    json.id   appointment.professional.id
    json.name appointment.professional.name
  else
    json.nil!
  end
end

# Computed
json.is_upcoming  appointment.upcoming?
json.is_past      appointment.past?
json.cancellable  appointment.cancellable?
json.reschedulable appointment.reschedulable?
