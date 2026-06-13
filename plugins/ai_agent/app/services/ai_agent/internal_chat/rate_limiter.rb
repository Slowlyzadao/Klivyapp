# Rate limit pra Pipeline B — máximo de N respostas da Bea por sala/dia.
# Conta lendo `internal_chat_messages` direto (sem tabela própria) — Bea
# já é distinguível por `sender_ai_agent_id`.
#
# Quando o limite é atingido, o Responder responde 1× com mensagem de
# silêncio e desiste das chamadas subsequentes do dia.
#
# Spec: docs/01-product/ai-agent-configuration-plan.md (Apêndice F.3)
module AiAgent::InternalChat::RateLimiter
  DEFAULT_DAILY_LIMIT = 30
  INSTALLATION_CONFIG_KEY = 'CAPTAIN_BEA_INTERNAL_CHAT_DAILY_LIMIT'.freeze

  Status = Struct.new(:allowed, :count, :limit, :over_limit, :already_notified, keyword_init: true) do
    def first_block?
      # Primeiro turno em que a Bea ultrapassou hoje — usado pra mandar a
      # mensagem de "passei do meu limite" UMA vez por sala/dia.
      over_limit && !already_notified
    end
  end

  def self.check(room:, bea:)
    limit = configured_limit
    count = todays_bea_messages(room, bea)
    notified = rate_limit_notice_already_today?(room, bea)

    Status.new(
      allowed: count < limit,
      count: count,
      limit: limit,
      over_limit: count >= limit,
      already_notified: notified
    )
  end

  def self.configured_limit
    raw = ::InstallationConfig.find_by(name: INSTALLATION_CONFIG_KEY)&.value
    Integer(raw)
  rescue StandardError, TypeError
    DEFAULT_DAILY_LIMIT
  end

  def self.todays_bea_messages(room, bea)
    ::InternalChat::Message
      .where(room_id: room.id, sender_ai_agent_id: bea.id)
      .where('created_at >= ?', Time.current.beginning_of_day)
      .count
  end

  def self.rate_limit_notice_already_today?(room, bea)
    ::InternalChat::Message
      .where(room_id: room.id, sender_ai_agent_id: bea.id)
      .where('created_at >= ?', Time.current.beginning_of_day)
      .exists?(["content_attributes ->> 'pipeline' = ?", 'internal_chat_rate_limit'])
  end
end
