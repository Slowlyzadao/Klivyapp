# frozen_string_literal: true

FactoryBot.define do
  factory :session_log do
    account
    patient { association :patient, account: account }
    professional { association :user, account: account }
    performed_at { Time.current }
    procedure_name { 'Aplicação de Toxina Botulínica' }
    status { 'draft' }
    return_needed { false }
    areas_treated { [] }
    products_used { [] }

    trait :signed do
      status { 'signed' }
      signed_at { Time.current }
      signed_by { association :user, account: account }
    end

    trait :erratum do
      signed
      erratum_at { Time.current }
      erratum_by { association :user, account: account }
      erratum_reason { 'Lote informado errado.' }
    end

    trait :patient_signed_local do
      patient_signature_blob { 'data:image/png;base64,iVBORw0KGgo=' }
      patient_signature_mode { 'local_tablet' }
      patient_signed_at { Time.current }
      patient_signature_integrity_hash { 'fakehash' }
      patient_signature_ip { '127.0.0.1' }
    end

    trait :with_remote_token do
      patient_signature_remote_token { SecureRandom.hex(32) }
      patient_signature_remote_link_sent_at { Time.current }
      patient_signature_remote_link_expires_at { 48.hours.from_now }
    end
  end
end
