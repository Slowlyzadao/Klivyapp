if ENV['SENTRY_DSN'].present?
  Sentry.init do |config|
    config.dsn = ENV['SENTRY_DSN']
    config.enabled_environments = %w[staging production]

    # To activate performance monitoring, set one of these options.
    # We recommend adjusting the value in production:
    config.traces_sample_rate = 0.1 if ENV['ENABLE_SENTRY_TRANSACTIONS']

    config.excluded_exceptions += ['Rack::Timeout::RequestTimeoutException']

    # AUDIT 2026-05-25 — invertido pra opt-in (era opt-out).
    # Default antigo (`true unless DISABLE_SENTRY_PII`) enviava request body,
    # headers e params do paciente pro Sentry sem flag explícita. Em prod
    # médico (LGPD/CFM), só ativa se ENABLE_SENTRY_PII=true estiver setado.
    # filter_parameters já mascara transcript/soap_structure, mas exceptions
    # podem carregar PII em mensagens livres — opt-in é a postura segura.
    config.send_default_pii = ENV['ENABLE_SENTRY_PII'].present?
  end
end
