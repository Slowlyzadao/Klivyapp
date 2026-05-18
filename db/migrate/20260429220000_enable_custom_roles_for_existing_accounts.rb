# Habilita o feature flag `custom_roles` para contas existentes e flipa o
# default na InstallationConfig — combina com a mudança em config/features.yml
# (`enabled: true`). O módulo de Funções Personalizadas (plugins/custom_roles)
# passa a ser ligado por padrão em toda nova conta, sem precisar do super_admin
# ativar manualmente em Super Admin > Contas.
class EnableCustomRolesForExistingAccounts < ActiveRecord::Migration[7.1]
  def up
    config = InstallationConfig.find_by(name: 'ACCOUNT_LEVEL_FEATURE_DEFAULTS')
    if config && config.value.present?
      features = config.value.map do |f|
        f['name'] == 'custom_roles' ? f.merge('enabled' => true) : f
      end
      config.value = features
      config.save!
    end

    Account.find_in_batches(batch_size: 100) do |accounts|
      accounts.each { |account| account.enable_features!('custom_roles') }
    end

    GlobalConfig.clear_cache
  end
end
