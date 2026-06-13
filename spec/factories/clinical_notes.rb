# frozen_string_literal: true

# `ClinicalNote` foi deprecado em [1.5.2.0] (unificação Procedimentos+Evolução).
# Esta factory é mantida exclusivamente para o spec de migração de backfill
# (BackfillClinicalNotesIntoSessionLogs). Não usar em features novas.
FactoryBot.define do
  factory :clinical_note do
    account
    patient { association :patient, account: account }
    professional { association :user, account: account }
    note_date { Date.current }
    complaint_of_day { 'Queixa de teste' }
    assessment { 'Avaliação clínica' }
    conduct { 'Procedimento realizado' }
    status { 'draft' }

    trait :signed do
      status { 'signed' }
      signed_at { Time.current }
      signed_by { association :user, account: account }
    end

    trait :soft_deleted do
      deleted_at { Time.current }
    end

    trait :with_return do
      return_recommended { Date.current + 14 }
    end
  end
end
