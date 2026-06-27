# Thin wrapper over RubyLLM embeddings. Stays independent from
# Captain::Llm::EmbeddingService so the plugin can evolve its own
# batching/retry policy without touching enterprise code.
#
# Embedding requests are cached in Redis keyed by `model + sha256(text)`
# for 30 days. Repeated FAQ queries cost zero after the first call,
# which matters at scale and especially for embedding the same chunks
# twice on document re-ingestion.
class AiAgent::Llm::EmbeddingClient
  class EmbeddingError < StandardError; end

  DEFAULT_MODEL = 'text-embedding-3-small'.freeze
  CACHE_TTL = 30.days.to_i

  # Cosseno entre dois vetores de embedding (utilitário compartilhado entre o
  # consolidador e o detector de duplicatas).
  def self.cosine(vec_a, vec_b)
    return 0.0 if vec_a.blank? || vec_b.blank? || vec_a.size != vec_b.size

    dot = norm_a = norm_b = 0.0
    vec_a.each_index do |i|
      dot += vec_a[i] * vec_b[i]
      norm_a += vec_a[i]**2
      norm_b += vec_b[i]**2
    end
    return 0.0 if norm_a.zero? || norm_b.zero?

    dot / (Math.sqrt(norm_a) * Math.sqrt(norm_b))
  end

  def initialize(model: nil)
    ::Llm::Config.initialize!
    @model = model.presence ||
             InstallationConfig.find_by(name: 'CAPTAIN_EMBEDDING_MODEL')&.value.presence ||
             DEFAULT_MODEL
  end

  def embed(text)
    return nil if text.to_s.strip.empty?

    cached = read_cache(text)
    return cached if cached

    vector = RubyLLM.embed(text, model: @model).vectors
    write_cache(text, vector)
    vector
  rescue StandardError => e
    Rails.logger.error("[AiAgent] embedding failed (#{e.class}): #{e.message}")
    raise EmbeddingError, e.message
  end

  # PERF-21 (auditoria 2026-05-18): pre-fetch do cache em 1 round-trip
  # Redis (MGET) em vez de N. Pra grandes documentos (50+ chunks) isso
  # corta ~100ms de latência só de network ida-volta repetido. Pra cache
  # misses ainda chamamos sequential (RubyLLM ainda não expõe batched
  # embedding uniformemente entre OpenAI/Gemini).
  #
  # Retorna array do MESMO TAMANHO que `texts`, mantendo ordem. Cada
  # posição é o vetor (Array<Float>) ou nil pra textos vazios.
  def embed_batch(texts)
    return [] if texts.empty?

    # Redis::Alfred não expõe MGET neste ambiente — busca chave a chave (o job é
    # async e os documentos de FAQ têm poucos chunks, então o custo é desprezível).
    keys = texts.filter_map { |t| t.to_s.strip.empty? ? nil : cache_key(t) }
    cached_by_key = keys.zip(keys.map { |k| ::Redis::Alfred.get(k) }).to_h

    texts.map { |text| text.to_s.strip.empty? ? nil : resolve_embedding(text, cached_by_key) }
  end

  # Vetor a partir do cache (raw já buscado) ou via embed quando ausente/corrompido.
  def resolve_embedding(text, cached_by_key)
    raw = cached_by_key[cache_key(text)]
    return embed_and_persist(text) if raw.blank?

    JSON.parse(raw)
  rescue JSON::ParserError
    embed_and_persist(text)
  end

  private

  def cache_key(text)
    "ai_agent:emb:#{@model}:#{Digest::SHA256.hexdigest(text)}"
  end

  def read_cache(text)
    raw = ::Redis::Alfred.get(cache_key(text))
    return nil if raw.blank?

    JSON.parse(raw)
  rescue JSON::ParserError
    nil
  end

  def write_cache(text, vector)
    ::Redis::Alfred.setex(cache_key(text), vector.to_json, CACHE_TTL)
  rescue StandardError => e
    Rails.logger.warn("[AiAgent] embedding cache write failed: #{e.message}")
  end

  # Embed + write_cache em 1 call. Usado pelos cache-miss do embed_batch
  # pra preservar a invariante de cache do path serial.
  def embed_and_persist(text)
    vector = RubyLLM.embed(text, model: @model).vectors
    write_cache(text, vector)
    vector
  rescue StandardError => e
    Rails.logger.error("[AiAgent] embedding failed (#{e.class}): #{e.message}")
    raise EmbeddingError, e.message
  end

  # Embed many strings in sequence. RubyLLM does not yet expose batched
  # embeddings uniformly across providers, so we keep this simple and
  # serial. Callers run inside a Sidekiq job so latency is acceptable.
  def embed_many(texts)
    texts.map { |t| embed(t) }
  end
end
