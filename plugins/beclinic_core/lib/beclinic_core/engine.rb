module BeclinicCore
  class Engine < ::Rails::Engine
    isolate_namespace BeclinicCore

    initializer 'beclinic_core.devise_mailer', after: :load_config_initializers do
      Devise.mailer = 'KlivyMailer'
    end

    config.after_initialize do
      plugin_locales = Dir[BeclinicCore::Engine.root.join('config/locales/**/*.yml').to_s]
      I18n.load_path -= plugin_locales
      I18n.load_path += plugin_locales
      I18n.backend.reload! if I18n.backend.respond_to?(:reload!)
    end

    config.to_prepare do
      Account.class_eval do
        has_one :beclinic_profile, class_name: 'BeclinicCore::AccountProfile', dependent: :destroy, autosave: true

        def beclinic_profile
          super || build_beclinic_profile
        end

        delegate :monthly_goal, :monthly_goal=,
                 :quarterly_goal, :quarterly_goal=,
                 :annual_goal, :annual_goal=,
                 :default_specialty, :default_specialty=,
                 :enabled_specialties, :enabled_specialties=,
                 to: :beclinic_profile
      end

      User.class_eval do
        include BeclinicPermissible
        has_one :beclinic_profile, class_name: 'BeclinicCore::UserProfile', dependent: :destroy, autosave: true

        def beclinic_profile
          super || build_beclinic_profile
        end

        delegate :agenda_public_id, :agenda_public_id=, to: :beclinic_profile
      end
    end
  end
end
