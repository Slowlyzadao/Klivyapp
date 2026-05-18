# Página dedicada para gerenciar o widget de suporte que aparece no canto
# inferior direito do dashboard do usuário. Mostra apenas os 3 campos que
# importam (ativar/desativar, websiteToken, baseUrl) — alternativa simples
# ao painel genérico de InstallationConfigs.
#
# Linkada em /super_admin/klivy_widget e exibida como sub-item do dropdown
# "Ajuda" da sidebar do Super Admin.
class SuperAdmin::KlivyWidgetsController < SuperAdmin::ApplicationController
  CONFIG_KEYS = %w[
    KLIVY_SUPPORT_WIDGET_ENABLED
    KLIVY_SUPPORT_WIDGET_TOKEN
    KLIVY_SUPPORT_WIDGET_URL
  ].freeze

  def show
    @widget_settings = load_settings
  end

  def update
    permitted = params.require(:widget).permit(*CONFIG_KEYS.map(&:downcase))

    CONFIG_KEYS.each do |key|
      next unless permitted.key?(key.downcase)

      value = sanitize_value(key, permitted[key.downcase])
      InstallationConfig
        .where(name: key)
        .first_or_create(value: value, locked: false)
        .update!(value: value)
    end

    GlobalConfig.clear_cache

    redirect_to super_admin_klivy_widget_url, notice: 'Configurações do widget atualizadas.'
  end

  private

  def load_settings
    CONFIG_KEYS.each_with_object({}) do |key, hash|
      hash[key] = InstallationConfig.find_by(name: key)&.value
    end
  end

  # Boolean precisa ser normalizado pra string 'true'/'false' (formato esperado
  # pelo vueapp.html.erb). Strings vão como-são (após strip).
  def sanitize_value(key, raw)
    if key == 'KLIVY_SUPPORT_WIDGET_ENABLED'
      ActiveModel::Type::Boolean.new.cast(raw).to_s
    else
      raw.to_s.strip
    end
  end
end
