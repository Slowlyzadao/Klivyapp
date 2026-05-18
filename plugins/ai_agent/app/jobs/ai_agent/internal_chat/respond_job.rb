module AiAgent
  module InternalChat
    # Roda o Pipeline B (Bea responde @beatriz) async via Sidekiq pra não
    # bloquear o fluxo do MessageDispatcher original. Latência da chamada
    # LLM (1-3s) ficaria visível pro usuário se síncrono.
    #
    # Spec: docs/01-product/ai-agent-configuration-plan.md (Apêndice F.3)
    class RespondJob < ApplicationJob
      queue_as :default

      def perform(message_id)
        AiAgent::InternalChat::Responder.respond(message_id: message_id)
      end
    end
  end
end
