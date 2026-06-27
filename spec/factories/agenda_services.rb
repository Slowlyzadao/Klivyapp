# frozen_string_literal: true

FactoryBot.define do
  factory :agenda_service do
    sequence(:name) { |n| "Serviço #{n}" }
    duration_minutes { 60 }
    # `price` foi movido pra Financial::ServicePricing em 2026-05-22 — a
    # coluna não existe mais em agenda_services. Setar aqui quebra com
    # NoMethodError 'price=', então foi removido.
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
