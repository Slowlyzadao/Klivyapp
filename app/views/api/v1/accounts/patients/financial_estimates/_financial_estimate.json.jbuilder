json.id financial_estimate.id
json.account_id financial_estimate.account_id
json.patient_id financial_estimate.patient_id
json.treatment_plan_id financial_estimate.treatment_plan_id
json.status financial_estimate.status
json.subtotal financial_estimate.subtotal.to_f
json.discount_type financial_estimate.discount_type
json.discount_value financial_estimate.discount_value.to_f
json.discount_amount financial_estimate.discount_amount.to_f
json.total financial_estimate.total.to_f
json.installments_count financial_estimate.installments_count
json.installment_value financial_estimate.installment_value.to_f
json.payment_method financial_estimate.payment_method
json.notes financial_estimate.notes
json.valid_until financial_estimate.valid_until
json.approved_at financial_estimate.approved_at
json.sent_at financial_estimate.sent_at
json.created_at financial_estimate.created_at
json.updated_at financial_estimate.updated_at

json.generated_by do
  if financial_estimate.generated_by
    json.id financial_estimate.generated_by.id
    json.name financial_estimate.generated_by.name
  else
    json.null!
  end
end

# KPIs financeiros do orçamento
json.financial_summary do
  json.total_paid financial_estimate.total_paid.to_f
  json.total_pending financial_estimate.total_pending.to_f
  json.total_overdue financial_estimate.total_overdue.to_f
end

# Transações vinculadas (resumo)
json.transactions financial_estimate.transactions.active.order(:due_date) do |transaction|
  json.id transaction.id
  json.amount transaction.amount.to_f
  json.status transaction.status
  json.due_date transaction.due_date
  json.paid_at transaction.paid_at
  json.payment_method transaction.payment_method
  json.installment_number transaction.installment_number
  json.total_installments transaction.total_installments
  json.description transaction.description
end
