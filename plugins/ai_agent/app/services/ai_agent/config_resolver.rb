# Resolves the effective configuration for an account by walking the 3-layer
# hierarchy (global → account → user) and clamping every account-level value
# against the global ceiling. Account values can never exceed global limits.
#
# Usage:
#   AiAgent::ConfigResolver.new(account).chat_model
#   AiAgent::ConfigResolver.new(account).max_tokens_per_conversation
class AiAgent::ConfigResolver
  def initialize(account)
    @account = account
    @global = AiAgent::GlobalSetting.current
    @account_setting = account&.ai_agent_setting
  end

  def enabled?
    return @global.enabled_by_default_for_new_accounts if @account_setting.nil?

    @account_setting.enabled
  end

  def chat_provider
    @global.chat_provider
  end

  def chat_model
    @account_setting&.chat_model.presence || @global.chat_model.presence
  end

  def max_tokens_per_conversation
    account_value = @account_setting&.max_tokens_per_conversation
    clamp_int(account_value, @global.max_tokens_per_conversation)
  end

  def monthly_token_budget
    @account_setting&.monthly_token_budget
  end

  def persona
    @account_setting&.persona || @global.default_persona
  end

  def system_prompt_prefix
    @account_setting&.system_prompt_prefix
  end

  def enabled_tools
    whitelist = @account_setting&.enabled_tools || []
    globally_enabled = AiAgent::ToolDefinition.enabled.pluck(:key)
    return globally_enabled if whitelist.blank?

    whitelist & globally_enabled
  end

  def over_monthly_cost_cap?
    return false if @account.nil? || @global.unlimited_monthly_cost?

    consumed = AiAgent::UsageCounter.monthly_cost_cents(account_id: @account.id)
    consumed >= @global.max_monthly_cost_per_account_cents
  end

  private

  # Account value cannot exceed the global ceiling. Nil = inherit global.
  def clamp_int(account_value, global_value)
    return global_value if account_value.nil?

    [account_value, global_value].min
  end
end
