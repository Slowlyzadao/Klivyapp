# frozen_string_literal: true

FactoryBot.define do
  factory :financial_entry, class: 'Financial::Entry' do
    account
    financial_bank_account { association :financial_bank_account, account: account }
    direction { 'in' }
    kind { 'receita' }
    amount_cents { 10_000 }
    competence_date { Date.current }
    cash_date { Date.current }
    description { 'Receita de teste' }
    affects_dre { true }
    affects_cashflow { true }

    trait :outflow do
      direction { 'out' }
      kind { 'despesa' }
    end

    trait :transfer do
      kind { 'transferencia' }
      affects_dre { false }
    end
  end
end
