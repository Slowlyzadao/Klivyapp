# frozen_string_literal: true

module Signatures
  # Resolve qual provider instanciar baseado em ENV / config / explicit.
  #
  # Resolução em ordem:
  #   1. Caller passou `name:` explícito → usa esse
  #   2. ENV['SIGNATURES_PROVIDER'] → 'mock' | 'clicksign'
  #   3. Default por ambiente: dev/test → mock, prod → clicksign
  #
  # Usado pelo SignatureRequestCreator e jobs de status sync. NÃO chamar
  # `.new` direto nos providers — sempre via resolver, pra centralizar a
  # configuração.
  module ProviderResolver
    module_function

    def for_name(name)
      case name.to_s
      when 'mock'      then Providers::MockProvider.new
      when 'clicksign' then Providers::ClicksignProvider.new
      else
        raise ProviderError, "Unknown provider: #{name.inspect}"
      end
    end

    def default
      name = ENV['SIGNATURES_PROVIDER'].presence || default_for_env
      for_name(name)
    end

    def default_name
      ENV['SIGNATURES_PROVIDER'].presence || default_for_env
    end

    def default_for_env
      Rails.env.production? ? 'clicksign' : 'mock'
    end
  end
end
