module AiAgent
  # Two layers of rate limiting on top of the model-provider's own quotas:
  #
  #   - per conversation: defends against stuck users / runaway loops
  #     (max turns / hour from a single conversation_id)
  #   - per account:      defends against billing surprises and abuse
  #     (max turns / day across the whole account)
  #
  # Both counters live in Redis with TTLs so they auto-expire — no cleanup
  # job needed. When a limit is hit, the listener skips enqueueing the job
  # and the user sees no reply (silent drop is the safe default for spam).
  class RateLimiter
    PER_CONVERSATION_LIMIT = 60     # turns per hour per conversation
    PER_CONVERSATION_TTL   = 1.hour
    PER_ACCOUNT_LIMIT      = 2000   # turns per day per account
    PER_ACCOUNT_TTL        = 1.day

    # Telemetria de rate-limit hits (separada dos counters de rate).
    # Permite o dashboard mostrar "X hits nos últimos 7d" sem mexer no
    # bucket que decide allow/deny. TTL longo o suficiente pra observar
    # padrão semanal de abuso.
    HIT_COUNTER_TTL = 7.days

    Decision = Struct.new(:allowed, :reason, :scope, keyword_init: true) do
      def allowed? = allowed
    end

    def initialize(account_id:, conversation_id:)
      @account_id = account_id
      @conversation_id = conversation_id
    end

    def check_and_increment
      conv = bump(conv_key, PER_CONVERSATION_TTL)
      return refuse('conversation', conv) if conv > PER_CONVERSATION_LIMIT

      acc = bump(account_key, PER_ACCOUNT_TTL)
      return refuse('account', acc) if acc > PER_ACCOUNT_LIMIT

      Decision.new(allowed: true)
    end

    def conv_count
      ::Redis::Alfred.get(conv_key).to_i
    end

    def account_count
      ::Redis::Alfred.get(account_key).to_i
    end

    private

    def bump(key, ttl)
      count = ::Redis::Alfred.incr(key)
      ::Redis::Alfred.expire(key, ttl.to_i) if count == 1
      count
    end

    def refuse(scope, count)
      record_hit_telemetry(scope)
      Decision.new(
        allowed: false,
        scope: scope,
        reason: "rate_limited:#{scope}:#{count}"
      )
    end

    # Conta o hit num bucket diário separado pra dashboard ler depois.
    # Não interfere no allow/deny — é só observabilidade.
    def record_hit_telemetry(scope)
      key = hit_key(scope)
      count = ::Redis::Alfred.incr(key)
      ::Redis::Alfred.expire(key, HIT_COUNTER_TTL.to_i) if count == 1
    rescue StandardError => e
      Rails.logger.warn("[AiAgent::RateLimiter] hit telemetry failed: #{e.class}: #{e.message}")
    end

    def conv_key = "ai_agent:rl:conv:#{@conversation_id}"
    def account_key = "ai_agent:rl:acc:#{@account_id}:#{Date.current}"
    def hit_key(scope) = "ai_agent:rl_hits:acc:#{@account_id}:#{Date.current}:#{scope}"

    # Class-level reader: agrega hits dos últimos N dias por account+scope.
    # Lê o range de chaves via Redis::Alfred. Retorna Hash { 'conversation' => 12, 'account' => 3 }.
    def self.hits_in_last_days(account_id:, days: 7)
      result = { 'conversation' => 0, 'account' => 0 }
      days.times do |i|
        date = (Date.current - i)
        result.each_key do |scope|
          key = "ai_agent:rl_hits:acc:#{account_id}:#{date}:#{scope}"
          result[scope] += ::Redis::Alfred.get(key).to_i
        end
      end
      result
    rescue StandardError
      result
    end
  end
end
