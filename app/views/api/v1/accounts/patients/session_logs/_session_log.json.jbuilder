json.extract! session_log,
              :id,
              :patient_id,
              :account_id,
              :treatment_plan_id,
              :treatment_item_id,
              :appointment_id,
              :performed_at,
              :duration_minutes,
              :areas_treated,
              :products_used,
              :complications,
              :result_observed,
              :post_procedure_guidance,
              :return_needed,
              :return_in_days,
              :created_at,
              :updated_at

json.professional_name    session_log.professional&.name
json.treatment_plan_title session_log.treatment_plan&.title
json.procedure_name       session_log.procedure_name.presence || session_log.treatment_item&.procedure_name
