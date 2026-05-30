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
# Em DEV, se `tmp/telemed-tunnels.json` existir (escrito pelo
# `plugins/telemed/bin/dev-bootstrap`), a URL do LiveKit é trocada pela URL
# pública do tunnel cloudflared (wss://*.trycloudflare.com). Sem isso, o
# token emitido pro paciente externo aponta pra ws://localhost:7880 — que
# não existe no laptop dele, e ainda é mixed-content quando a página vem
# por HTTPS. As credenciais (key/secret) seguem vindo do ENV ou defaults.
#
# Service idempotente, leitura pura. Sem side effects.
module Telemed
  class CredentialsResolver
    DEV_DEFAULTS = {
      url:        'ws://localhost:7880',
      api_key:    'devkey',
      api_secret: 'secret'
    }.freeze

    DEV_TUNNELS_FILE = 'tmp/telemed-tunnels.json'

    Credentials = Struct.new(:url, :api_key, :api_secret, :source, keyword_init: true) do
      def configured?
        url.present? && api_key.present? && api_secret.present?
      end

      def dev_mode?
        source == :dev_defaults || source == :dev_tunnel
      end
    end

    def initialize(account:)
      @account = account
    end

    def call
      creds = from_account_setting || from_env || from_dev_defaults
      apply_dev_tunnel_override(creds)
    end

    private

    # Override só da URL quando o dev-bootstrap subiu um tunnel pro LiveKit.
    # Account setting (caso self_hosted real) NÃO é sobrescrito — a clínica
    # tem URL própria e deve ser respeitada mesmo em dev.
    def apply_dev_tunnel_override(creds)
      return creds unless Rails.env.development?
      return creds if creds.source == :account_setting

      tunnel_url = dev_tunnel_livekit_url
      return creds unless tunnel_url

      Credentials.new(
        url:        tunnel_url,
        api_key:    creds.api_key,
        api_secret: creds.api_secret,
        source:     :dev_tunnel
      )
    end

    def dev_tunnel_livekit_url
      path = Rails.root.join(DEV_TUNNELS_FILE)
      return nil unless File.exist?(path)

      JSON.parse(File.read(path))['livekit_url'].presence
    rescue StandardError => e
      Rails.logger.warn("[CredentialsResolver] falha ao ler #{DEV_TUNNELS_FILE}: #{e.class}: #{e.message}")
      nil
    end

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
