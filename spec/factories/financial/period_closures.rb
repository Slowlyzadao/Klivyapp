# frozen_string_literal: true

FactoryBot.define do
  factory :financial_period_closure, class: 'Financial::PeriodClosure' do
    account
    period_year { Date.current.year }
    period_month { Date.current.month }
    closed_at { Time.current }
    closed_by { association :user }
    status { 'closed' }
  end
end
