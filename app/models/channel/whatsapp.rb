class Channel::Whatsapp < ApplicationRecord
  include Channelable
  include Reauthorizable

  self.table_name = 'channel_whatsapp'
  EDITABLE_ATTRS = [:phone_number, :provider, { provider_config: {} }].freeze

  PROVIDERS = %w[default whatsapp_cloud whatsapp_qr].freeze

  before_validation :ensure_webhook_verify_token

  validates :provider, inclusion: { in: PROVIDERS }
  validates :phone_number, presence: true, uniqueness: true
  validate :validate_provider_config

  after_create :sync_templates
  before_destroy :teardown_webhooks
  after_commit :setup_webhooks, on: :create, if: :should_auto_setup_webhooks?

  def name
    'Whatsapp'
  end

  def provider_service
    if provider == 'whatsapp_cloud'
      Whatsapp::Providers::WhatsappCloudService.new(whatsapp_channel: self)
    elsif provider == 'whatsapp_qr'
      # Retorna o serviço que criamos para o QR Code
      Whatsapp::Providers::WhatsappQrService.new(whatsapp_channel: self)
    else
      Whatsapp::Providers::Whatsapp360DialogService.new(whatsapp_channel: self)
    end
  end

  def mark_message_templates_updated
    update_column(:message_templates_last_updated, Time.zone.now)
  end

  delegate :send_message, to: :provider_service
  delegate :send_template, to: :provider_service
  delegate :sync_templates, to: :provider_service
  delegate :media_url, to: :provider_service
  delegate :api_headers, to: :provider_service

  def setup_webhooks
    return if provider == 'whatsapp_qr'

    perform_webhook_setup
  rescue StandardError => e
    Rails.logger.error "[WHATSAPP] Webhook setup failed: #{e.message}"
    prompt_reauthorization!
  end

  private

  def ensure_webhook_verify_token
    provider_config['webhook_verify_token'] ||= SecureRandom.hex(16) if provider == 'whatsapp_cloud'
  end

  def validate_provider_config
    # IGNORA validação se for o nosso motor de QR Code
    return if provider == 'whatsapp_qr'

    errors.add(:provider_config, 'Invalid Credentials') unless provider_service.validate_provider_config?
  end

  def perform_webhook_setup
    return if provider == 'whatsapp_qr'

    business_account_id = provider_config['business_account_id']
    api_key = provider_config['api_key']

    Whatsapp::WebhookSetupService.new(self, business_account_id, api_key).perform
  end

  def teardown_webhooks
    if provider == 'whatsapp_qr'
      disconnect_qr_bridge
      return
    end
    Whatsapp::WebhookTeardownService.new(self).perform
  end

  def disconnect_qr_bridge
    bridge_url = ENV.fetch('WHATSAPP_QR_BRIDGE_URL') { ENV.fetch('WHATSAPP_BRIDGE_URL', 'http://localhost:3002') }
    uri = URI("#{bridge_url}/sessions/#{id}/disconnect")
    Net::HTTP.post_form(uri, {})
    Rails.logger.info "[WHATSAPP_QR] Sessão #{id} desconectada do bridge com sucesso."
  rescue StandardError => e
    Rails.logger.warn "[WHATSAPP_QR] Falha ao desconectar bridge na deleção: #{e.message}"
  end

  def should_auto_setup_webhooks?
    return false if provider == 'whatsapp_qr'

    provider == 'whatsapp_cloud' && provider_config['source'] != 'embedded_signup'
  end
end
