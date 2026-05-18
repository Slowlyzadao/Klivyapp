module AiAgent
  # Bea needs a Chatwoot identity to be the `sender` of outgoing messages.
  # We use a single global AgentBot row created on first use; this is enough
  # for the MVP and avoids per-account bot proliferation.
  module AgentBotIdentity
    NAME = 'Bea'.freeze

    def self.ensure!
      AgentBot.find_or_create_by!(name: NAME) do |bot|
        bot.description = 'Klivy AI Agent (Bea) — single-agent virtual assistant.'
        bot.outgoing_url = nil # internal, no webhook
      end
    end
  end
end
