require_relative 'preset_definitions'

module CustomRoles
  # Service idempotente que garante que cada conta tem os 4 presets KlivyRole
  # (Recepcionista/Especialista/Gerente/SDR) com permissões corretas.
  #
  # Comportamento (importante — preserva customizações):
  #
  #   - Preset NÃO EXISTE  → cria com `permissions` do preset.
  #   - Preset existe e está CORROMPIDO (`permissions` vazio OU todas false)
  #     → restaura (caso encontrado durante auditoria — bug Gerente all-false).
  #   - Preset existe e tem ao menos uma perm true → **SKIP** (admin pode ter
  #     customizado intencionalmente — não sobrescreve).
  #   - `force: true` → sobrescreve sempre (uso em dev/teste; nunca usar em prod
  #     sem comunicar usuários porque apaga customização).
  #
  # Reusos:
  #   - Rake `custom_roles:seed_presets` (varre todas contas).
  #   - `Account.after_create` hook (cria os 4 quando conta nasce).
  #   - Pode ser chamado manualmente no console pra reparar conta específica.
  class PresetSeeder
    Result = Struct.new(:created, :restored, :skipped, :force_updated, keyword_init: true)

    def self.call(account, force: false, logger: nil)
      new(account, force: force, logger: logger).call
    end

    def initialize(account, force: false, logger: nil)
      @account = account
      @force = force
      @logger = logger
      @result = Result.new(created: [], restored: [], skipped: [], force_updated: [])
    end

    def call
      PresetDefinitions::ALL.each { |preset| process(preset) }
      @result
    end

    private

    def process(preset)
      existing = @account.klivy_roles.find_by(name: preset[:label])

      if existing.nil?
        create(preset)
      elsif @force
        force_update(existing, preset)
      elsif corrupted?(existing)
        restore(existing, preset)
      else
        skip(preset)
      end
    end

    def create(preset)
      @account.klivy_roles.create!(
        name: preset[:label],
        description: preset[:description],
        preset_key: preset[:preset_key],
        permissions: preset[:permissions]
      )
      @result.created << preset[:label]
      log("[CREATED] account=#{@account.id} preset=#{preset[:preset_key]}")
    end

    def restore(role, preset)
      role.update!(
        permissions: preset[:permissions],
        # Preserva preset_key existente se já tem (pode estar custom); usa o
        # canônico se estiver vazio.
        preset_key: role.preset_key.presence || preset[:preset_key]
      )
      @result.restored << preset[:label]
      log("[RESTORED] account=#{@account.id} preset=#{preset[:preset_key]} (era corrompido)")
    end

    def force_update(role, preset)
      role.update!(
        description: preset[:description],
        preset_key: preset[:preset_key],
        permissions: preset[:permissions]
      )
      @result.force_updated << preset[:label]
      log("[FORCED] account=#{@account.id} preset=#{preset[:preset_key]}")
    end

    def skip(preset)
      @result.skipped << preset[:label]
      log("[SKIP]    account=#{@account.id} preset=#{preset[:preset_key]} (customizado)")
    end

    # "Corrompido" = sem nenhuma permissão `true` no JSONB. Cobre os casos:
    #   - permissions == {} (vazio)
    #   - todas as keys boolean são false (ex: editor abriu e salvou em estado
    #     vazio — caso real encontrado com o preset Gerente da conta 31).
    def corrupted?(role)
      perms = role.permissions || {}
      return true if perms.empty?

      perms.values.all? do |mod_perms|
        next true unless mod_perms.is_a?(Hash)

        mod_perms.except('scope').values.none? { |v| v == true }
      end
    end

    def log(message)
      @logger&.info(message) || puts(message)
    end
  end
end
