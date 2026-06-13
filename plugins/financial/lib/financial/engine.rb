# Carrega o módulo Financial e seus componentes em lib/ que NÃO são autoloaded
# por convenção (Engine só carrega lib/financial/engine.rb via Dir.glob no
# config/application.rb). O require_relative aqui garante que `Financial::Gateways`,
# `Financial::Gateways::Base/Manual/Asaas` e `Financial::Errors` estejam definidos
# antes do controller `Api::V1::Accounts::Financial::BaseController` ser carregado
# e referenciar `Financial::Gateways::GatewayError` no rescue_from.
require_relative '../financial'

module Financial
  class Engine < ::Rails::Engine
    isolate_namespace Financial

    config.to_prepare do
      # Associações do canon V2 (namespace `Financial::*`).
      #
      # NÃO usar dependent: :destroy_async aqui — soft delete em todas as
      # tabelas via Financial::Concerns::SoftDeletable. Limpeza física só por
      # job admin com auditoria + backup.
      #
      # Legacy "Onda 1A" (sem namespace) foi removido em 2026-05-22:
      # tabelas dropadas em `drop_legacy_financial_tables`, models/controllers
      # deletados. Sem cliente real → clean break.
      #
      # Bootstrap automático (2026-05-23): toda Account nova ganha o canon
      # completo de DreCategory via after_create_commit. Onboarding deixa
      # de exigir seed manual via `rails runner`. Idempotente — accounts
      # antigas com seed manual não duplicam.
      Account.class_eval do
        has_many :financial_dre_categories,        class_name: 'Financial::DreCategory',         foreign_key: :account_id
        has_many :financial_bank_accounts,         class_name: 'Financial::BankAccount',         foreign_key: :account_id
        has_many :financial_payment_methods,       class_name: 'Financial::PaymentMethod',       foreign_key: :account_id
        has_many :financial_payment_method_fees,   class_name: 'Financial::PaymentMethodFee',    foreign_key: :account_id
        has_many :financial_commission_rules,      class_name: 'Financial::CommissionRule',      foreign_key: :account_id
        has_many :financial_recurring_expenses,    class_name: 'Financial::RecurringExpense',    foreign_key: :account_id
        has_many :financial_revenue_goals,         class_name: 'Financial::RevenueGoal',         foreign_key: :account_id
        has_many :financial_service_pricings,      class_name: 'Financial::ServicePricing',      foreign_key: :account_id
        has_many :financial_agent_profiles,        class_name: 'Financial::AgentProfile',        foreign_key: :account_id
        has_many :financial_budgets,               class_name: 'Financial::Budget',              foreign_key: :account_id
        has_many :financial_budget_items,          class_name: 'Financial::BudgetItem',          foreign_key: :account_id
        has_many :financial_installments,          class_name: 'Financial::Installment',         foreign_key: :account_id
        has_many :financial_payment_receipts,      class_name: 'Financial::PaymentReceipt',      foreign_key: :account_id
        has_many :financial_payment_receipt_items, class_name: 'Financial::PaymentReceiptItem',  foreign_key: :account_id
        has_many :financial_expenses,              class_name: 'Financial::Expense',             foreign_key: :account_id
        has_many :financial_entries,               class_name: 'Financial::Entry',               foreign_key: :account_id
        has_many :financial_commission_entries,    class_name: 'Financial::CommissionEntry',     foreign_key: :account_id
        has_many :financial_refunds,               class_name: 'Financial::Refund',              foreign_key: :account_id
        has_many :financial_cash_registers,        class_name: 'Financial::CashRegister',        foreign_key: :account_id
        has_many :financial_cash_movements,        class_name: 'Financial::CashMovement',        foreign_key: :account_id
        has_many :financial_patient_credits,       class_name: 'Financial::PatientCredit',       foreign_key: :account_id
        has_many :financial_audit_logs,            class_name: 'Financial::AuditLog',            foreign_key: :account_id
        has_many :financial_period_closures,       class_name: 'Financial::PeriodClosure',       foreign_key: :account_id
        has_many :financial_idempotency_keys,      class_name: 'Financial::IdempotencyKey',      foreign_key: :account_id
        has_one  :financial_setup_state,           class_name: 'Financial::SetupState',          foreign_key: :account_id
        has_one  :financial_gateway_setting,       class_name: 'Financial::GatewaySetting',      foreign_key: :account_id
        has_many :financial_gateway_webhook_events, class_name: 'Financial::GatewayWebhookEvent', foreign_key: :account_id
        has_many :financial_lgpd_requests,         class_name: 'Financial::LgpdRequest',         foreign_key: :account_id

        # Bootstrap canon: roda em background após commit do Account#create.
        # Usa `perform_later` pra não bloquear o request de onboarding —
        # categoria DRE pode demorar ~200ms criando ~80 registros.
        #
        # Guard `defined?` evita quebra durante boot/migrate quando o
        # Financial engine ainda não foi carregado completamente.
        after_create_commit do
          if defined?(::Financial::Bootstrap::SeedDefaultCategories) && defined?(::Financial::BootstrapAccountJob)
            ::Financial::BootstrapAccountJob.perform_later(id)
          elsif defined?(::Financial::Bootstrap::SeedDefaultCategories)
            # Fallback síncrono — só se o job class ainda não foi carregada
            # (improvável em runtime normal). Mantém comportamento previsível
            # em testes que não usam ActiveJob queue.
            ::Financial::Bootstrap::SeedDefaultCategories.call(account: self)
          end
        rescue StandardError => e
          # Não fazer Account.create falhar se o bootstrap der ruim.
          # Operador resolve manualmente via Configurações > Restaurar padrão.
          Rails.logger.error("[Financial bootstrap] Account ##{id} bootstrap failed: #{e.message}")
        end
      end
    end
  end
end
