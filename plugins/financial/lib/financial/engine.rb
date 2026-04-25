module Financial
  class Engine < ::Rails::Engine
    isolate_namespace Financial

    config.to_prepare do
      Account.class_eval do
        has_many :financial_categories, dependent: :destroy_async
        has_many :bank_accounts, dependent: :destroy_async
        has_many :account_transactions, dependent: :destroy_async
        has_many :commission_rules, dependent: :destroy_async
        has_many :recurring_expenses, dependent: :destroy_async
        has_many :cash_registers, dependent: :destroy_async
        has_many :cash_register_entries, dependent: :destroy_async
      end
    end
  end
end
