# Resolve credenciais LiveKit pra uma account (Sprint K — Telemedicina).
#
# Hierarquia (mais específico vence):
#   1. Setting da clínica `telemedicine: { mode: 'self_hosted', ... }`
#      → clínica trouxe próprias credenciais
#   2. ENV vars (LIVEKIT_URL, LIVEKIT_API_KEY, LIVEKIT_API_SECRET)
#      → instalação Klivy-hosted padrão
#   3. Defaults dev (ws://localhost:7880, devkey/secret)
#      → `livekit-server --dev` rodando local
#
# Service idempotente, leitura pura. Sem side effects.
module Telemed
  class CredentialsResolver
    DEV_DEFAULTS = {
      url:        'ws://localhost:7880',
      api_key:    'devkey',
      api_secret: 'secret'
    }.freeze

    Credentials = Struct.new(:url, :api_key, :api_secret, :source, keyword_init: true) do
      def configured?
        url.present? && api_key.present? && api_secret.present?
      end

      def dev_mode?
        source == :dev_defaults
      end
    end

    def initialize(account:)
      @account = account
    end

    def call
      from_account_setting || from_env || from_dev_defaults
    end

    private

    def from_account_setting
      cfg = @account&.patient_portal_setting&.scheduling&.dig('telemedicine')
      return nil unless cfg.is_a?(Hash)
      return nil unless cfg['mode'].to_s == 'self_hosted'
      return nil if cfg['api_key'].blank? || cfg['api_secret'].blank? || cfg['url'].blank?

      Credentials.new(
        url:        cfg['url'],
        api_key:    cfg['api_key'],
        api_secret: cfg['api_secret'],
        source:     :account_setting
      )
    end

    def from_env
      url    = ENV['LIVEKIT_URL'].presence
      key    = ENV['LIVEKIT_API_KEY'].presence
      secret = ENV['LIVEKIT_API_SECRET'].presence
      return nil unless url && key && secret

      Credentials.new(url: url, api_key: key, api_secret: secret, source: :env)
    end

    def from_dev_defaults
      Credentials.new(**DEV_DEFAULTS, source: :dev_defaults)
    end
  end
end
