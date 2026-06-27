# BE-24 (auditoria 2026-05-18): circuit breaker no provider primário.
# Quando ele falha N vezes em janela curta, abre o circuit — pula
# direto pro fallback (OpenAI) sem mais tentativas no primary. Evita
# cada turn pagar latência de 2s+ esperando primary que está
# comprovadamente fora. Após COOLDOWN sem tentativa, o circuit fecha
# naturalmente (TTL no Redis) e re-tenta primary.
#
# Extraído de `AiAgent::ChatService` (Fase 4 / BE-1) pra modularizar
# o orquestrador. Sem state interno — chama `::Redis::Alfred` (ou um
# stub injetado) por parâmetro `redis:`, fail-open em qualquer erro.
#
# Constantes `CIRCUIT_BREAKER_*` ficam em ChatService (preservação de
# API pública) — este módulo só lê pelo namespace pai em runtime, NÃO
# em class-body eval (evita load-order bug do Zeitwerk).
class AiAgent::ChatService::CircuitBreaker
  # Retorna true se o circuit pro `model` está aberto (>= THRESHOLD
  # falhas na janela atual). Fail-open em Redis down — preserva
  # comportamento original do ChatService.
  #
  # @param model [String] nome do modelo (ex: "gemini-3-flash-preview")
  # @param redis [Object] cliente Redis (default ::Redis::Alfred)
  # @return [Boolean]
  def self.open?(model, redis: ::Redis::Alfred)
    count = redis.get(key_for(model)).to_i
    count >= AiAgent::ChatService::CIRCUIT_BREAKER_THRESHOLD
  rescue StandardError => e
    Rails.logger.warn("[AiAgent] circuit check failed: #{e.message}")
    false
  end

  # Registra falha do provider, incrementa contador e seta TTL na
  # primeira falha da janela. Fail-open em Redis down.
  #
  # @param model [String]
  # @param redis [Object] cliente Redis (default ::Redis::Alfred)
  def self.record_failure(model, redis: ::Redis::Alfred)
    key = key_for(model)
    count = redis.incr(key)
    redis.expire(key, AiAgent::ChatService::CIRCUIT_BREAKER_COOLDOWN.to_i) if count == 1
  rescue StandardError => e
    Rails.logger.warn("[AiAgent] circuit record_failure failed: #{e.message}")
  end

  # Chave Redis bucketed por janela. Mantém o mesmo formato que estava
  # inline no ChatService — não muda contadores existentes em Redis.
  def self.key_for(model)
    "ai_agent:circuit:#{model}:#{(Time.current.to_i / AiAgent::ChatService::CIRCUIT_BREAKER_WINDOW.to_i)}"
  end
end
