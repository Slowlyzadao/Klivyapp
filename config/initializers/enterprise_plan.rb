# Garante que o plano Enterprise esteja sempre ativo em toda inicialização.
# Isso é necessário porque o ConfigLoader (reconcile_only_new: true) não sobrescreve
# valores existentes, e o banco pode ter sido criado com plano 'community'.
# O CHATWOOT_HUB_URL=https://hub.invalid/# no Dockerfile impede que o job
# CheckNewVersionsJob sobrescreva esses valores de volta.
Rails.application.config.after_initialize do
  # Pula durante asset precompile (não há DB nesse contexto)
  next if ENV['SECRET_KEY_BASE'] == 'precompile_placeholder'

  begin
    next unless ActiveRecord::Base.connection.table_exists?('installation_configs')

    [
      { name: 'INSTALLATION_PRICING_PLAN', value: 'enterprise' },
      { name: 'INSTALLATION_PRICING_PLAN_QUANTITY', value: 10_000 }
    ].each do |entry|
      config = InstallationConfig.find_or_initialize_by(name: entry[:name])
      next if config.persisted? && config.value == entry[:value]

      config.value = entry[:value]
      config.locked = false
      config.save!
      Rails.logger.info "[ENTERPRISE] #{entry[:name]} = #{entry[:value]} ✅"
    end
  rescue StandardError => e
    Rails.logger.warn "[ENTERPRISE] Skipping plan enforcement (DB not ready): #{e.message}"
  end
end
