# Prepended onto Captain::Conversation::ResponseBuilderJob so the
# Chatwoot-legacy auto-response pipeline becomes a no-op whenever the
# assistant attached to the inbox is our system assistant "Beatriz".
# Bea's own pipeline (AiAgent::EventListeners::MessageListener →
# AiAgent::ChatResponseJob) handles the reply, with a different (and
# correct) knowledge base. Other Captain::Assistant rows on the same
# account still go through the legacy path normally.
#
# NESTED MODULE INTENTIONAL: este arquivo é `require_relative`'d na
# primeira linha de `engine.rb`, ANTES do Zeitwerk autoload definir
# `module AiAgent`. Usar `module AiAgent::SkipBeatrizLegacyResponse`
# (compact) explode com `uninitialized constant AiAgent`. A forma nested
# define `AiAgent` implicitamente — única forma que funciona aqui.
# rubocop:disable Style/ClassAndModuleChildren
module AiAgent
  module SkipBeatrizLegacyResponse
    def perform(conversation, assistant)
      if assistant.respond_to?(:name) && assistant.name == 'Beatriz'
        Rails.logger.info(
          '[AiAgent] skipping legacy Captain::ResponseBuilderJob for Beatriz ' \
          "(conv=#{conversation.respond_to?(:id) ? conversation.id : conversation})"
        )
        return
      end
      super
    end
  end
end
# rubocop:enable Style/ClassAndModuleChildren
