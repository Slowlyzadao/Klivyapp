class GlobalConfig
  VERSION = 'V1'.freeze
  KEY_PREFIX = 'GLOBAL_CONFIG'.freeze
  DEFAULT_EXPIRY = 1.day

  class << self
    def get(*args)
      config_keys = args.flatten
      cache_keys  = config_keys.map { |config_key| cache_key_for(config_key) }

      # Um único round-trip pro Redis em vez de 1 GET por chave (eram ~22 GETs
      # seriais por render do dashboard/login). O fallback pro banco + set só
      # roda em cache miss (cold cache), idêntico ao comportamento anterior.
      cached_values = $alfred.with do |conn|
        conn.pipelined { |pipeline| cache_keys.each { |ck| pipeline.get(ck) } }
      end

      config = {}
      config_keys.each_with_index do |config_key, index|
        raw_value = cached_values[index]

        if raw_value.blank?
          raw_value = { value: db_fallback(config_key) }.to_json
          $alfred.with { |conn| conn.set(cache_keys[index], raw_value, { ex: DEFAULT_EXPIRY }) }
        end

        config[config_key] = JSON.parse(raw_value)['value']
      end

      typecast_config(config)
      config.with_indifferent_access
    end

    def get_value(arg)
      load_from_cache(arg)
    end

    def clear_cache
      cached_keys = $alfred.with { |conn| conn.keys("#{VERSION}:#{KEY_PREFIX}:*") }
      (cached_keys || []).each do |cached_key|
        $alfred.with { |conn| conn.expire(cached_key, 0) }
      end
    end

    private

    def cache_key_for(config_key)
      "#{VERSION}:#{KEY_PREFIX}:#{config_key}"
    end

    def typecast_config(config)
      general_configs = ConfigLoader.new.general_configs
      config.each do |config_key, config_value|
        config_type = general_configs.find { |c| c['name'] == config_key }&.dig('type')
        config[config_key] = ActiveRecord::Type::Boolean.new.cast(config_value) if config_type == 'boolean'
      end
    end

    def load_from_cache(config_key)
      cache_key = cache_key_for(config_key)
      cached_value = $alfred.with { |conn| conn.get(cache_key) }

      if cached_value.blank?
        value_from_db = db_fallback(config_key)
        cached_value = { value: value_from_db }.to_json
        $alfred.with { |conn| conn.set(cache_key, cached_value, { ex: DEFAULT_EXPIRY }) }
      end

      JSON.parse(cached_value)['value']
    end

    def db_fallback(config_key)
      InstallationConfig.find_by(name: config_key)&.value
    end
  end
end
