module Patients
  class Engine < ::Rails::Engine
    isolate_namespace Patients

    config.to_prepare do
      # Injeção de dependências no Core
      Account.class_eval do
        has_many :patients, dependent: :destroy
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
