json.transactions @transactions do |transaction|
  json.partial! 'api/v1/accounts/patients/transactions/transaction', transaction: transaction
end

json.meta do
  json.total_count @transactions.total_count if @transactions.respond_to?(:total_count)
  json.page params[:page] || 1
  json.per_page params[:per_page] || 25
end
