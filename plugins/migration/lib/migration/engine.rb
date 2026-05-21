module Migration
  class Engine < ::Rails::Engine
    engine_name 'migration'

    initializer :append_migration_migrations do |app|
      app.config.paths['db/migrate'] << root.join('db/migrate').to_s
      ActiveRecord::Migrator.migrations_paths << root.join('db/migrate').to_s
    end

    config.to_prepare do
      Account.class_eval do
        has_many :migration_runs, dependent: :destroy_async, class_name: 'MigrationRun'
      end
    end
  end
end
