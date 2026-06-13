module Patients
  class Engine < ::Rails::Engine
    isolate_namespace Patients

    config.to_prepare do
      # Injeção de dependências no Core
      Account.class_eval do
        has_many :patients, dependent: :destroy

        # Habilita as feature flags do módulo financeiro v2 automaticamente
        # para toda nova account:
        #   - `financial_timeline_v2` (PR 3 do refactor 2026-05-06)
        #   - `payment_plan_wizard_v2` (F3 do PaymentPlanWizardV2, 1.8.0.24)
        #
        # Backfills correspondentes: migrations `20260507000001` e
        # `20260527000001` cuidam das accounts existentes na adoção.
        # `unless method_defined?` evita re-registrar callback em hot reload.
        unless method_defined?(:_enable_patients_default_beta_features)
          before_create :_enable_patients_default_beta_features

          DEFAULT_FINANCIAL_BETA_FEATURES = %w[
            financial_timeline_v2
            payment_plan_wizard_v2
          ].freeze

          define_method(:_enable_patients_default_beta_features) do
            key = 'beta_features'
            existing = Array(custom_attributes&.dig(key)).map(&:to_s)
            to_add = DEFAULT_FINANCIAL_BETA_FEATURES - existing
            return if to_add.empty?

            self.custom_attributes = (custom_attributes || {}).merge(
              key => (existing + to_add).uniq
            )
          end
        end
      end

      Contact.class_eval do
        has_one :patient, dependent: :nullify
      end

      User.class_eval do
        has_many :responsible_patients, class_name: 'Patient', foreign_key: 'responsible_professional_id', dependent: :nullify
      end
    end
  end
end
