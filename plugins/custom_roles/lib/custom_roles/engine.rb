module CustomRoles
  class Engine < ::Rails::Engine
    engine_name 'custom_roles'

    initializer :append_custom_roles_migrations do |app|
      app.config.paths['db/migrate'] << root.join('db/migrate').to_s
      ActiveRecord::Migrator.migrations_paths << root.join('db/migrate').to_s
    end

    # Carrega os módulos do `lib/` que não seguem convenção Zeitwerk
    # (PresetDefinitions e PresetSeeder são plain Ruby modules em `lib/`).
    initializer :require_custom_roles_lib do
      require_relative 'preset_definitions'
      require_relative 'preset_seeder'
    end

    # Rake tasks do plugin (`custom_roles:seed_presets`).
    rake_tasks do
      load File.expand_path('../tasks/custom_roles.rake', __dir__)
    end

    config.to_prepare do
      Account.class_eval do
        has_many :klivy_roles, dependent: :destroy_async, class_name: 'KlivyRole'

        # Cria os 4 presets Klivy (Recepcionista/Especialista/Gerente/SDR)
        # automaticamente em contas novas. Idempotente — se a conta já tem
        # algum preset (caso de seed manual ou re-execução), o PresetSeeder
        # pula sem overwrite (preserva customização do admin).
        after_create :seed_klivy_presets

        def seed_klivy_presets
          CustomRoles::PresetSeeder.call(self)
        rescue StandardError => e
          # Best-effort: criação de conta NÃO deve falhar por causa de seed
          # de presets. Em prod, vale rodar `rake custom_roles:seed_presets`
          # depois pra reparar contas que falharam aqui.
          Rails.logger.error("[CustomRoles::PresetSeeder] failed for account=#{id}: #{e.class}: #{e.message}")
        end
      end

      AccountUser.class_eval do
        belongs_to :klivy_role, class_name: 'KlivyRole', optional: true

        # Resolves whether this account_user appears as a provider on the
        # agenda calendar. Resolution order:
        #   1. `account_users.is_agenda_provider` (explicit per-user override)
        #   2. Chatwoot `administrator` (dono da clínica) → default true
        #   3. `klivy_role.permissions['agenda']['is_provider']` (role default)
        #   4. `false`
        #
        # `has_attribute?` guards against the migration not having run yet —
        # in that state we simply fall back to the role default so the agents
        # API keeps working instead of 500ing.
        def agenda_provider?
          if has_attribute?(:is_agenda_provider) && !is_agenda_provider.nil?
            return is_agenda_provider
          end
          # Administradores (dono da clínica que assinou o plano) defaultam
          # pra TRUE — geralmente são profissionais clínicos. Se não forem,
          # o admin desliga o toggle "Atende na agenda" no editor.
          return true if administrator?
          return false unless klivy_role

          klivy_role.can?(:agenda, :is_provider)
        end
      end
    end
  end
end
