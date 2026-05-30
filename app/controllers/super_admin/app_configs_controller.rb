class SuperAdmin::AppConfigsController < SuperAdmin::ApplicationController
  before_action :set_config
  before_action :allowed_configs
  def show
    # ref: https://github.com/rubocop/rubocop/issues/7767
    # rubocop:disable Style/HashTransformValues
    @app_config = InstallationConfig.where(name: @allowed_configs)
                                    .pluck(:name, :serialized_value)
                                    .map { |name, serialized_value| [name, serialized_value['value']] }
                                    .to_h
    # rubocop:enable Style/HashTransformValues
    @installation_configs = ConfigLoader.new.general_configs.each_with_object({}) do |config_hash, result|
      result[config_hash['name']] = config_hash.except('name')
    end
  end

  def create
    errors = []
    params['app_config'].each do |key, value|
      next unless @allowed_configs.include?(key)

      i = InstallationConfig.where(name: key).first_or_create(value: value, locked: false)
      i.value = value
      errors.concat(i.errors.full_messages) unless i.save
    end

    if errors.any?
      redirect_to super_admin_app_config_path(config: @config), alert: errors.join(', ')
    else
      redirect_to super_admin_settings_path, notice: "App Configs - #{@config.titleize} updated successfully"
    end
  end

  # Sprint L — testa conexão com provider de IA (OpenAI Whisper / Anthropic
  # Claude). Faz uma chamada barata (modelos listing) pra validar a chave
  # SEM consumir tokens significativos. Retorna JSON pra o frontend mostrar
  # status sem reload da página.
  def test_connection
    provider = params[:provider].to_s
    result = case provider
             when 'openai_whisper'
               test_openai_whisper
             when 'anthropic'
               test_anthropic
             else
               { ok: false, message: "Provider desconhecido: #{provider}" }
             end

    render json: result
  end

  private

  def set_config
    @config = params[:config] || 'general'
  end

  def allowed_configs
    mapping = {
      'facebook' => %w[FB_APP_ID FB_VERIFY_TOKEN FB_APP_SECRET IG_VERIFY_TOKEN FACEBOOK_API_VERSION ENABLE_MESSENGER_CHANNEL_HUMAN_AGENT],
      'shopify' => %w[SHOPIFY_CLIENT_ID SHOPIFY_CLIENT_SECRET],
      'microsoft' => %w[AZURE_APP_ID AZURE_APP_SECRET],
      'email' => %w[MAILER_INBOUND_EMAIL_DOMAIN ACCOUNT_EMAILS_LIMIT ACCOUNT_EMAILS_PLAN_LIMITS],
      'linear' => %w[LINEAR_CLIENT_ID LINEAR_CLIENT_SECRET],
      'slack' => %w[SLACK_CLIENT_ID SLACK_CLIENT_SECRET],
      'instagram' => %w[INSTAGRAM_APP_ID INSTAGRAM_APP_SECRET INSTAGRAM_VERIFY_TOKEN INSTAGRAM_API_VERSION ENABLE_INSTAGRAM_CHANNEL_HUMAN_AGENT],
      'tiktok' => %w[TIKTOK_APP_ID TIKTOK_APP_SECRET TIKTOK_API_VERSION],
      'whatsapp_embedded' => %w[WHATSAPP_APP_ID WHATSAPP_APP_SECRET WHATSAPP_CONFIGURATION_ID WHATSAPP_API_VERSION],
      'notion' => %w[NOTION_CLIENT_ID NOTION_CLIENT_SECRET],
      'google' => %w[GOOGLE_OAUTH_CLIENT_ID GOOGLE_OAUTH_CLIENT_SECRET GOOGLE_OAUTH_REDIRECT_URI ENABLE_GOOGLE_OAUTH_LOGIN],
      'captain' => %w[CAPTAIN_OPEN_AI_API_KEY CAPTAIN_OPEN_AI_MODEL CAPTAIN_OPEN_AI_ENDPOINT],
      # Sprint L — Teleconsulta: chaves de IA pra transcricao (Whisper) e
      # evolucao SOAP (Claude). Mesma UI dos demais app_configs.
      # 2026-05-25 — Removidos GEMINI_API_KEY e TELEMED_GEMINI_REVIEW.
      # A camada de pós-revisão Gemini foi descontinuada do pipeline de
      # transcrição (não trouxe ganho perceptível vs gpt-4o-transcribe-diarize).
      'ai' => %w[
        OPENAI_WHISPER_KEY
        ANTHROPIC_API_KEY
        ANTHROPIC_MODEL
        TELEMED_AI_PROVIDER_DEFAULT
      ]
    }

    @allowed_configs = mapping.fetch(
      @config,
      %w[ENABLE_ACCOUNT_SIGNUP FIREBASE_PROJECT_ID FIREBASE_CREDENTIALS WEBHOOK_TIMEOUT MAXIMUM_FILE_UPLOAD_SIZE WIDGET_TOKEN_EXPIRY]
    )
  end

  # Sprint L — Whisper validation: GET /v1/models retorna lista (auth check
  # barato, sem custo). Resposta 200 = chave válida.
  def test_openai_whisper
    key = InstallationConfig.find_by(name: 'OPENAI_WHISPER_KEY')&.value.presence ||
          InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_API_KEY')&.value
    return { ok: false, message: 'Nenhuma chave OpenAI configurada' } if key.blank?

    require 'net/http'
    uri = URI('https://api.openai.com/v1/models')
    http = Net::HTTP.new(uri.host, uri.port).tap { |h| h.use_ssl = true; h.read_timeout = 10 }
    req = Net::HTTP::Get.new(uri).tap { |r| r['Authorization'] = "Bearer #{key}" }
    resp = http.request(req)

    if resp.is_a?(Net::HTTPSuccess)
      { ok: true, message: 'Conexão OK — chave OpenAI válida' }
    else
      { ok: false, message: "OpenAI rejeitou (HTTP #{resp.code}): #{resp.body.to_s.first(200)}" }
    end
  rescue StandardError => e
    { ok: false, message: "Erro de rede: #{e.class}: #{e.message.first(200)}" }
  end

  # Sprint L — Anthropic validation: chama /v1/models (mesmo padrão). Custo
  # zero — só auth check.
  def test_anthropic
    key = InstallationConfig.find_by(name: 'ANTHROPIC_API_KEY')&.value
    return { ok: false, message: 'Nenhuma chave Anthropic configurada' } if key.blank?

    require 'net/http'
    uri = URI('https://api.anthropic.com/v1/models')
    http = Net::HTTP.new(uri.host, uri.port).tap { |h| h.use_ssl = true; h.read_timeout = 10 }
    req = Net::HTTP::Get.new(uri).tap do |r|
      r['x-api-key']         = key
      r['anthropic-version'] = '2023-06-01'
    end
    resp = http.request(req)

    if resp.is_a?(Net::HTTPSuccess)
      { ok: true, message: 'Conexão OK — chave Anthropic válida' }
    else
      { ok: false, message: "Anthropic rejeitou (HTTP #{resp.code}): #{resp.body.to_s.first(200)}" }
    end
  rescue StandardError => e
    { ok: false, message: "Erro de rede: #{e.class}: #{e.message.first(200)}" }
  end

end

SuperAdmin::AppConfigsController.prepend_mod_with('SuperAdmin::AppConfigsController')
