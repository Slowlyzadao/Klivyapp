# frozen_string_literal: true

FactoryBot.define do
  factory :treatment_plan do
    account
    patient { association :patient, account: account }
    professional { association :user, account: account }
    sequence(:title) { |n| "Plano #{n}" }
    description { 'Justificativa clínica do plano' }
    status { 'proposto' }

    trait :aprovado do
      status { 'aprovado' }
      approved_at { Time.current }
      approved_by { association :user, account: account }
    end

    trait :em_execucao do
      status { 'em_execucao' }
    end
  end
end
