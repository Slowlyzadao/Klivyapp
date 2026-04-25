json.financial_estimates @estimates do |estimate|
  json.partial! 'api/v1/accounts/patients/financial_estimates/financial_estimate', financial_estimate: estimate
end

json.meta do
  json.total @estimates.total_count if @estimates.respond_to?(:total_count)
end
