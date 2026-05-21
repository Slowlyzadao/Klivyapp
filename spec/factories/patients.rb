# frozen_string_literal: true

FactoryBot.define do
  factory :patient do
    account
    sequence(:name) { |n| "Paciente Teste #{n}" }
    patient_status { 'novo' }
    sex { 'masculino' }
  end
end
