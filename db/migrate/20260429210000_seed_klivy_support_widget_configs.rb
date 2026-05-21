# Popula as 3 InstallationConfig do Klivy Support Widget definidas em
# `config/installation_config.yml` na entrada `KLIVY_SUPPORT_WIDGET_*`.
#
# Por que migration: o ConfigLoader que lê o YAML só roda em `db:seed`
# (db/seeds.rb) ou no rake `db:enhancements`. Em ambientes que já tinham
# o app rodando antes desta versão, as keys novas não existem no banco
# e o vueapp.html.erb cai no fallback (widget escondido).
#
# Idempotente: usa first_or_create para não sobrescrever valores que o
# Super Admin já tenha editado.
class SeedKlivySupportWidgetConfigs < ActiveRecord::Migration[7.1]
  CONFIGS = [
    { name: 'KLIVY_SUPPORT_WIDGET_ENABLED', value: 'true' },
    { name: 'KLIVY_SUPPORT_WIDGET_TOKEN',   value: 'RroQdfAJ1m2m93Fx43sUMSNZ' },
    { name: 'KLIVY_SUPPORT_WIDGET_URL',     value: 'https://waha-chatwoot.efqhwo.easypanel.host' }
  ].freeze

  def up
    CONFIGS.each do |attrs|
      InstallationConfig.where(name: attrs[:name])
                        .first_or_create(value: attrs[:value], locked: false)
    end

    GlobalConfig.clear_cache
  end

  def down
    InstallationConfig.where(name: CONFIGS.pluck(:name)).destroy_all
    GlobalConfig.clear_cache
  end
end
