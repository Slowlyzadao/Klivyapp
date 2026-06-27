# frozen_string_literal: true

FactoryBot.define do
  factory :financial_dre_category, class: 'Financial::DreCategory' do
    account
    sequence(:name) { |n| "Categoria DRE #{n}" }
    kind { 'receita' }
    active { true }
    level { 1 }

    trait :expense do
      kind { 'despesa' }
    end
  end
end
