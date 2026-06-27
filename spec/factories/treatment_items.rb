# frozen_string_literal: true

FactoryBot.define do
  factory :treatment_item do
    account
    treatment_plan { association :treatment_plan, account: account }
    sequence(:procedure_name) { |n| "Procedimento #{n}" }
    region { 'Geral' }
    sessions_planned { 1 }
    sessions_done { 0 }
    unit_price { 100.00 }
    status { 'proposto' }
    discount_value { 0 }
  end
end
