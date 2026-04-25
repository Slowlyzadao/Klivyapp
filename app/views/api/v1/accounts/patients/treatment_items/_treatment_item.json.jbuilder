json.extract! treatment_item,
              :id,
              :treatment_plan_id,
              :procedure_code,
              :procedure_name,
              :region,
              :tooth_number,
              :sessions_planned,
              :sessions_done,
              :unit_price,
              :total_price,
              :priority,
              :status,
              :clinical_justification,
              :notes,
              :created_at,
              :updated_at

json.remaining_sessions    treatment_item.remaining_sessions
json.completion_percentage treatment_item.completion_percentage
