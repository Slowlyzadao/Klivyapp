# frozen_string_literal: true

FactoryBot.define do
  factory :agenda_event do
    sequence(:title) { |n| "Consulta #{n}" }
    description { 'Consulta de rotina' }
    starts_at { 1.day.from_now.beginning_of_hour }
    ends_at { 1.day.from_now.beginning_of_hour + 1.hour }
    status { 'scheduled' }
    event_type { 'consultation' }
    custom_attributes { {} }

    after(:build) do |event|
      event.account ||= create(:account)
      event.user ||= create(:user, account: event.account, role: :agent)
      event.contact ||= create(:contact, account: event.account)
    end

    trait :confirmed do
      status { 'confirmed' }
    end

    trait :cancelled do
      status { 'cancelled' }
    end

    trait :completed do
      status { 'completed' }
    end

    # Sprint K — evento configurado como teleconsulta. O flag mora em
    # custom_attributes pra reaproveitar a infra do patient_portal
    # (Telemed::Session lê desse JSONB).
    trait :telemedicine do
      custom_attributes { { 'telemedicine_enabled' => true } }
    end
  end
end
