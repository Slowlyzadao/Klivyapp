# Carrega o módulo Financial e seus componentes em lib/ que NÃO são autoloaded
# por convenção (Engine só carrega lib/financial/engine.rb via Dir.glob no
# config/application.rb). O require_relative aqui garante que `Financial::Gateways`,
# `Financial::Gateways::Base/Manual/Asaas` estejam definidos antes do controller
# `Api::V1::Accounts::Financial::BaseController` ser carregado e referenciar
# `Financial::Gateways::GatewayError` no rescue_from.
require_relative '../financial'

module Financial
  class Engine < ::Rails::Engine
    isolate_namespace Financial

    config.to_prepare do
      Account.class_eval do
        # Onda 1A — modelos legados (mantidos até validação da v2).
        has_many :financial_categories, dependent: :destroy_async
        has_many :bank_accounts, dependent: :destroy_async
        has_many :account_transactions, dependent: :destroy_async
        has_many :commission_rules, dependent: :destroy_async
        has_many :recurring_expenses, dependent: :destroy_async
        has_many :cash_registers, dependent: :destroy_async
        has_many :cash_register_entries, dependent: :destroy_async

        # Financeiro v2 — namespace Financial::*.
        # Não usar dependent: :destroy_async aqui: soft delete em todas as tabelas
        # via Financial::Concerns::SoftDeletable. Limpeza física só por job admin.
        has_many :financial_dre_categories,    class_name: 'Financial::DreCategory',     foreign_key: :account_id
        has_many :financial_bank_accounts,     class_name: 'Financial::BankAccount',     foreign_key: :account_id
        has_many :financial_commission_rules,  class_name: 'Financial::CommissionRule',  foreign_key: :account_id
        has_many :financial_recurring_expenses, class_name: 'Financial::RecurringExpense', foreign_key: :account_id
        has_many :financial_revenue_goals,     class_name: 'Financial::RevenueGoal',     foreign_key: :account_id
        has_many :financial_budgets,           class_name: 'Financial::Budget',          foreign_key: :account_id
        has_many :financial_installments,      class_name: 'Financial::Installment',     foreign_key: :account_id
        has_many :financial_payment_receipts,  class_name: 'Financial::PaymentReceipt',  foreign_key: :account_id
        has_many :financial_expenses,          class_name: 'Financial::Expense',         foreign_key: :account_id
        has_many :financial_entries,           class_name: 'Financial::Entry',           foreign_key: :account_id
        has_many :financial_commission_entries, class_name: 'Financial::CommissionEntry', foreign_key: :account_id
        has_many :financial_cash_registers,    class_name: 'Financial::CashRegister',    foreign_key: :account_id
        has_many :financial_cash_movements,    class_name: 'Financial::CashMovement',    foreign_key: :account_id
        has_many :financial_audit_logs,        class_name: 'Financial::AuditLog',        foreign_key: :account_id
        has_many :financial_patient_credits,   class_name: 'Financial::PatientCredit',   foreign_key: :account_id
        has_one  :financial_setup_state,       class_name: 'Financial::SetupState',      foreign_key: :account_id
        has_one  :financial_gateway_setting,   class_name: 'Financial::GatewaySetting',  foreign_key: :account_id
      end
    end
  end
end
