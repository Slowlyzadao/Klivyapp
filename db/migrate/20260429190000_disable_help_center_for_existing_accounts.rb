# Desabilita o feature flag `help_center` para contas existentes e flipa o
# default na InstallationConfig — combina com a mudança em config/features.yml
# (`enabled: false`). A Central de Ajuda nativa do Chatwoot foi substituída
# pelo módulo customizado `plugins/ajuda/`, então o item "Help Center" não
# precisa mais aparecer marcado no painel de Features do Super Admin.
class DisableHelpCenterForExistingAccounts < ActiveRecord::Migration[7.1]
  def up
    config = InstallationConfig.find_by(name: 'ACCOUNT_LEVEL_FEATURE_DEFAULTS')
    if config && config.value.present?
      features = config.value.map do |f|
        f['name'] == 'help_center' ? f.merge('enabled' => false) : f
      end
      config.value = features
      config.save!
    end

    Account.find_in_batches(batch_size: 100) do |accounts|
      accounts.each { |account| account.disable_features!('help_center') }
    end

    GlobalConfig.clear_cache
  end
end
