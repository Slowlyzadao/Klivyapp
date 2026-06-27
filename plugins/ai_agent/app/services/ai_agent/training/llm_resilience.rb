# Resiliência compartilhada das chamadas LLM do treinamento (FaqExtractor e
# FaqValidator): retry com backoff exponencial em erro TRANSITÓRIO (rate-limit
# de RPM, 5xx, timeout), distinção de erro DEFINITIVO (crédito/billing/auth —
# não adianta repetir) e a sentinela UNAVAILABLE que o job usa pra falhar
# visível e reprocessar, em vez de aceitar resultado parcial em silêncio.
module AiAgent::Training::LlmResilience
  MAX_RETRIES = 3          # tentativas extras por modelo em erro transitório
  BASE_BACKOFF = 2.0       # segundos; cresce exponencial (2, 4, 8…) + jitter

  # Sentinela distinta de `nil`: o modelo ficou INDISPONÍVEL mesmo após os
  # retries. Diferente de `[]` (rodou e não achou nada).
  UNAVAILABLE = :extraction_unavailable

  private

  # Roda o bloco com retry/backoff no erro transitório. Retorna o resultado do
  # bloco, `[]` em erro definitivo de conteúdo (aceita e segue) ou UNAVAILABLE
  # se esgotar os retries com o provider fora.
  def with_model_retries(model)
    attempt = 0
    begin
      yield
    rescue StandardError => e
      if retryable?(e) && (attempt += 1) <= MAX_RETRIES
        sleep(backoff_seconds(attempt))
        retry
      end
      Rails.logger.warn("[#{self.class.name}] #{model} #{e.class}: #{e.message.to_s[0, 180]}")
      retryable?(e) ? UNAVAILABLE : []
    end
  end

  # Chat configurado pro modelo: credencial do Gemini injetada (o core só
  # injeta a da OpenAI), temperatura 0 e thinking desligado (Gemini Flash).
  def build_chat(model)
    ::Llm::Config.initialize!
    wire_gemini_credentials!
    provider = provider_for(model)
    chat = RubyLLM.chat(model: model, provider: provider, assume_model_exists: true).with_temperature(0)
    disable_thinking(chat, provider)
    chat
  end

  # Transitório (vale retry): rate-limit de RPM, indisponibilidade, timeout.
  # NÃO transitório (não adianta repetir): crédito esgotado, billing, auth.
  def retryable?(error)
    message = error.message.to_s
    return false if message.match?(/deplet|billing|insufficient|quota exceeded|invalid.*key|unauthor|forbidden/i)

    klass = error.class.name.to_s
    klass.match?(/RateLimit|ServerError|ServiceUnavailable|Overload|Timeout/i) ||
      message.match?(/rate.?limit|timeout|temporar|overload|try again|throttl|\b(429|500|502|503|504)\b/i)
  end

  def backoff_seconds(attempt)
    (BASE_BACKOFF * (2**(attempt - 1))) + rand
  end

  def provider_for(model)
    model.to_s.include?('gemini') ? :gemini : :openai
  end

  # O core só injeta a credencial da OpenAI no RubyLLM; a do Gemini é nossa.
  def wire_gemini_credentials!
    key = InstallationConfig.find_by(name: 'CAPTAIN_GEMINI_API_KEY')&.value
    RubyLLM.config.gemini_api_key = key if key.present?
  rescue StandardError => e
    Rails.logger.warn("[#{self.class.name}] gemini creds: #{e.message}")
  end

  # Numa extração estruturada, o "thinking" do Gemini Flash só gasta token e
  # latência — desliga (mesmo workaround da Bea).
  def disable_thinking(chat, provider)
    return unless provider == :gemini

    chat.with_params(generationConfig: { thinkingConfig: { thinkingBudget: 0 } })
  rescue StandardError
    nil
  end
end
