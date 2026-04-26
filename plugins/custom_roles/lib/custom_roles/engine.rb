module CustomRoles
  class Engine < ::Rails::Engine
    engine_name 'custom_roles'

    initializer :append_custom_roles_migrations do |app|
      app.config.paths['db/migrate'] << root.join('db/migrate').to_s
      ActiveRecord::Migrator.migrations_paths << root.join('db/migrate').to_s
    end

    config.to_prepare do
      Account.class_eval do
        has_many :klivy_roles, dependent: :destroy_async, class_name: 'KlivyRole'
      end

      AccountUser.class_eval do
        belongs_to :klivy_role, class_name: 'KlivyRole', optional: true
      end
    end
  end
end
