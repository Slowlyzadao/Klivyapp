json.id transaction.id
json.account_id transaction.account_id
json.patient_id transaction.patient_id
json.financial_estimate_id transaction.financial_estimate_id
json.transaction_type transaction.transaction_type
json.amount transaction.amount.to_f
json.payment_method transaction.payment_method
json.status transaction.status
json.due_date transaction.due_date
json.paid_at transaction.paid_at
json.description transaction.description
json.notes transaction.notes
json.installment_number transaction.installment_number
json.total_installments transaction.total_installments
json.cash_entry_id transaction.cash_entry_id
json.created_at transaction.created_at
json.updated_at transaction.updated_at

json.registered_by do
  if transaction.registered_by
    json.id transaction.registered_by.id
    json.name transaction.registered_by.name
  else
    json.null!
  end
end

# Parcelas (se parcelado)
if transaction.parcelado?
  json.installments transaction.installments.active.order(:number) do |installment|
    json.id installment.id
    json.number installment.number
    json.amount installment.amount.to_f
    json.status installment.status
    json.due_date installment.due_date
    json.paid_at installment.paid_at
    json.payment_method installment.payment_method
    json.cash_entry_id installment.cash_entry_id
  end
end

json.is_overdue transaction.overdue?
json.is_parcelado transaction.parcelado?

# Comprovante de pagamento
mirror = ::AccountTransaction.find_by(source_transaction_id: transaction.id)

if transaction.payment_proof.attached?
  json.payment_proof_url rails_blob_path(transaction.payment_proof, only_path: true)
  json.payment_proof_filename transaction.payment_proof.filename.to_s
elsif mirror&.payment_proof&.attached?
  json.payment_proof_url rails_blob_path(mirror.payment_proof, only_path: true)
  json.payment_proof_filename mirror.payment_proof.filename.to_s
else
  json.payment_proof_url nil
  json.payment_proof_filename nil
end
