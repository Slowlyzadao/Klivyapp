# frozen_string_literal: true

FactoryBot.define do
  factory :anamnesis do
    account
    patient { association :patient, account: account }
    specialty { 'Odontologia Geral' }
    status { 'draft' }
    medical_history { {} }
    allergies { [] }
    current_medications { [] }
    contraindications { [] }
    relevant_habits { {} }
    pregnancy { {} }
  end
end
