# Página dedicada para o super admin configurar a Bea (agente de IA da Klivy).
# Substitui o painel genérico de InstallationConfigs por uma UI focada nas
# chaves que importam: provider ativo, OpenAI, Gemini e embedding model.
#
# Linkada em /super_admin/bea como item da sidebar do Super Admin.
class SuperAdmin::BeaController < SuperAdmin::ApplicationController
  # Chaves do InstallationConfig editáveis nesta página. Nome histórico,
  # cobre provider + system prompt + chat interno + health monitor.
  PROVIDER_KEYS = %w[
    CAPTAIN_LLM_PROVIDER
    CAPTAIN_OPEN_AI_API_KEY
    CAPTAIN_OPEN_AI_MODEL
    CAPTAIN_OPEN_AI_ENDPOINT
    CAPTAIN_GEMINI_API_KEY
    CAPTAIN_GEMINI_MODEL
    CAPTAIN_EMBEDDING_MODEL
    CAPTAIN_BEA_SYSTEM_PROMPT
    CAPTAIN_BEA_INTERNAL_CHAT_SYSTEM_PROMPT
    CAPTAIN_BEA_INTERNAL_CHAT_DAILY_LIMIT
    AI_AGENT_HEALTH_SLACK_WEBHOOK
    AI_AGENT_HEALTH_ALERT_EMAILS
  ].freeze

  ALLOWED_PROVIDERS = %w[openai gemini].freeze

  def show
    @settings = load_settings
    @stats = compute_stats
    @default_system_prompt = AiAgent::PromptBuilder::DEFAULT_PERSONA_PROMPT
    @default_internal_chat_prompt = AiAgent::InternalChat::SystemPrompt::DEFAULT
    @default_internal_chat_daily_limit = AiAgent::InternalChat::RateLimiter::DEFAULT_DAILY_LIMIT
  end

  def update
    permitted = params.require(:bea).permit(*PROVIDER_KEYS.map(&:downcase))
    errors = []
    diff = {}

    PROVIDER_KEYS.each do |key|
      next unless permitted.key?(key.downcase)

      value = sanitize_value(key, permitted[key.downcase])
      config = InstallationConfig.where(name: key).first_or_create(value: value, locked: false)
      old_value = config.value.to_s
      config.value = value
      if config.save
        diff[key] = { from: redact_for_audit(key, old_value), to: redact_for_audit(key, value.to_s) } if old_value != value.to_s
      else
        errors.concat(config.errors.full_messages)
      end
    end

    AiAgent::AuditLog.record(
      scope: 'global',
      action: 'update_provider_settings',
      actor: current_super_admin,
      ip: request.remote_ip,
      changes: diff
    ) if diff.any?

    Llm::Config.reset!

    if errors.any?
      redirect_to super_admin_bea_url, alert: errors.join(', ')
    else
      redirect_to super_admin_bea_url, notice: 'Configurações da Bea atualizadas.'
    end
  end

  private

  def load_settings
    PROVIDER_KEYS.each_with_object({}) do |key, hash|
      hash[key] = InstallationConfig.find_by(name: key)&.value
    end
  end

  def sanitize_value(key, raw)
    value = raw.to_s.strip
    return 'openai' if key == 'CAPTAIN_LLM_PROVIDER' && !ALLOWED_PROVIDERS.include?(value)

    value
  end

  # Hide secret material in audit log: keep only a fingerprint of API keys.
  def redact_for_audit(key, value)
    return value unless key.include?('API_KEY')
    return '(empty)' if value.blank?

    "#{value[0, 4]}…#{value[-4, 4]}"
  end

  def compute_stats
    since = 30.days.ago
    traces = AiAgent::Trace.where(created_at: since..)
    feedbacks = AiAgent::Feedback.where(created_at: since..)

    total = traces.count
    escalated = traces.where(escalated: true).count
    deflection_rate = total.zero? ? 0.0 : ((total - escalated).to_f / total * 100).round(1)

    avg_latency = traces.where.not(latency_ms: nil).average(:latency_ms)&.to_i || 0
    total_cost_cents = traces.sum(:cost_cents)
    total_tokens = traces.sum('input_tokens + output_tokens')

    sentiment_avg = traces.where.not(sentiment_score: nil).average(:sentiment_score)&.to_f&.round(3) || 0.0
    guardrail_blocks = traces.where("jsonb_array_length(guardrail_violations) > 0").count

    thumbs_up = feedbacks.positive.count
    thumbs_down = feedbacks.negative.count
    csat_pct = (thumbs_up + thumbs_down).zero? ? nil : (thumbs_up.to_f / (thumbs_up + thumbs_down) * 100).round(1)

    top_tools = traces.where("jsonb_array_length(tool_calls) > 0")
                      .pluck(:tool_calls)
                      .flatten
                      .map { |tc| tc['name'] || tc[:name] }
                      .compact
                      .tally
                      .sort_by { |_k, v| -v }
                      .first(8)

    {
      total_turns: total,
      escalated: escalated,
      deflection_rate: deflection_rate,
      avg_latency_ms: avg_latency,
      total_cost_cents: total_cost_cents,
      total_tokens: total_tokens,
      sentiment_avg: sentiment_avg,
      guardrail_blocks: guardrail_blocks,
      thumbs_up: thumbs_up,
      thumbs_down: thumbs_down,
      csat_pct: csat_pct,
      top_tools: top_tools,
      sentinel_enabled: sentinel_enabled?,
      rate_limit_hits_7d: rate_limit_hits_7d
    }
  end

  def sentinel_enabled?
    AiAgent::Humanization::Sentinel.enabled?
  rescue StandardError
    false
  end

  # Total agregado de rate-limit hits dos últimos 7 dias somando todas as
  # contas. Em escalas maiores (50+ contas) considerar mover pra Redis SCAN
  # com pattern. Pra agora (poucas contas) somar é OK.
  def rate_limit_hits_7d
    Account.pluck(:id).sum do |id|
      AiAgent::RateLimiter.hits_in_last_days(account_id: id, days: 7).values.sum
    end
  rescue StandardError
    0
  end
end
