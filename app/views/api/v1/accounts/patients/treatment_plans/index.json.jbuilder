json.data do
  json.array! @treatment_plans do |treatment_plan|
    json.partial! 'api/v1/accounts/patients/treatment_plans/treatment_plan', treatment_plan: treatment_plan
  end
end
