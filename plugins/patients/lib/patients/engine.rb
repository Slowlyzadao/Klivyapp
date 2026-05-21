module Patients
  class Engine < ::Rails::Engine
    isolate_namespace Patients

    config.to_prepare do
      # Injeção de dependências no Core
      Account.class_eval do
        has_many :patients, dependent: :destroy

        # Habilita a feature flag `financial_timeline_v2` (PR 3 do refactor
        # financeiro 2026-05-06) automaticamente para toda nova account.
        # Migration `20260507000001` faz o backfill para accounts existentes.
        # `unless method_defined?` evita re-registrar callback em hot reload.
        unless method_defined?(:_enable_patients_default_beta_features)
          before_create :_enable_patients_default_beta_features

          define_method(:_enable_patients_default_beta_features) do
            key = 'beta_features'
            existing = Array(custom_attributes&.dig(key)).map(&:to_s)
            return if existing.include?('financial_timeline_v2')

            self.custom_attributes = (custom_attributes || {}).merge(
              key => existing | ['financial_timeline_v2']
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
