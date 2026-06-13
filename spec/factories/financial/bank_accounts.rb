# frozen_string_literal: true

FactoryBot.define do
  factory :financial_bank_account, class: 'Financial::BankAccount' do
    account
    sequence(:name) { |n| "Conta Bancária #{n}" }
    kind { 'checking' }
    initial_balance_cents { 0 }
    active { true }

    trait :cash do
      kind { 'cash' }
      name { 'Caixa Físico' }
    end
  end
end
