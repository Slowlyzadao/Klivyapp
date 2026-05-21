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
              :discount_type,
              :discount_value,
              :priority,
              :status,
              :clinical_justification,
              :notes,
              :agenda_service_id,
              :created_at,
              :updated_at

json.remaining_sessions    treatment_item.remaining_sessions
json.completion_percentage treatment_item.completion_percentage
json.gross_subtotal        treatment_item.gross_subtotal
json.discount_amount       treatment_item.discount_amount
json.net_subtotal          treatment_item.net_subtotal

# PR #6b: snapshot inline do serviço atual (referência viva). Permite que o
# frontend exiba o nome CORRENTE quando o item está em modo de edição, sem
# perder o `procedure_name` histórico (audit trail do plano original).
if treatment_item.agenda_service.present?
  json.agenda_service do
    json.id treatment_item.agenda_service.id
    json.name treatment_item.agenda_service.name
    json.color treatment_item.agenda_service.color
    json.price treatment_item.agenda_service.price
    json.duration_minutes treatment_item.agenda_service.duration_minutes
    json.deleted_at treatment_item.agenda_service.deleted_at
  end
end
