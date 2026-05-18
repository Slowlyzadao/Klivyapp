module AiAgent
  module Llm
    # Thin wrapper over RubyLLM embeddings. Stays independent from
    # Captain::Llm::EmbeddingService so the plugin can evolve its own
    # batching/retry policy without touching enterprise code.
    #
    # Embedding requests are cached in Redis keyed by `model + sha256(text)`
    # for 30 days. Repeated FAQ queries cost zero after the first call,
    # which matters at scale and especially for embedding the same chunks
    # twice on document re-ingestion.
    class EmbeddingClient
      class EmbeddingError < StandardError; end

      DEFAULT_MODEL = 'text-embedding-3-small'.freeze
      CACHE_TTL = 30.days.to_i

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

      # Embed many strings in sequence. RubyLLM does not yet expose batched
      # embeddings uniformly across providers, so we keep this simple and
      # serial. Callers run inside a Sidekiq job so latency is acceptable.
      def embed_many(texts)
        texts.map { |t| embed(t) }
      end
    end
  end
end
