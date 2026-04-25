json.extract! treatment_plan,
              :id,
              :patient_id,
              :account_id,
              :title,
              :description,
              :status,
              :partially_approved,
              :approved_at,
              :cancellation_reason,
              :created_at,
              :updated_at,
              :estimated_duration

json.professional_name treatment_plan.professional&.name
json.approved_by_name  treatment_plan.approved_by&.name

json.pdf_url rails_blob_url(treatment_plan.pdf, only_path: true) if treatment_plan.pdf.attached?

json.summary do
  json.total_items treatment_plan.treatment_items.where(deleted_at: nil).count
  json.total_sessions_planned treatment_plan.total_sessions_planned
  json.total_sessions_done    treatment_plan.total_sessions_done
  json.completion_percentage  treatment_plan.completion_percentage
  json.total_value            treatment_plan.total_planned
end

json.treatment_items treatment_plan.treatment_items.where(deleted_at: nil).order(:created_at) do |item|
  json.partial! 'api/v1/accounts/patients/treatment_items/treatment_item', treatment_item: item
end
