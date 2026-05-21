# frozen_string_literal: true

FactoryBot.define do
  factory :agenda_service do
    sequence(:name) { |n| "Serviço #{n}" }
    duration_minutes { 60 }
    price { 100.0 }
    requires_room { false }
    color { '#3b82f6' }

    after(:build) do |service|
      service.account ||= create(:account)
    end

    trait :requires_room do
      requires_room { true }
    end

    trait :discarded do
      deleted_at { Time.current }
    end
  end
end
