# Roda o Pipeline B (Bea responde @beatriz) async via Sidekiq pra não
# bloquear o fluxo do MessageDispatcher original. Latência da chamada
# LLM (1-3s) ficaria visível pro usuário se síncrono.
#
# Spec: docs/01-product/ai-agent-configuration-plan.md (Apêndice F.3)
class AiAgent::InternalChat::RespondJob < ApplicationJob
  queue_as :default

  # account_id é opcional pra compatibilidade com jobs já enfileirados
  # antes desse fix. Novos enqueues sempre passam — listener atualizado.
  def perform(message_id, account_id: nil)
    AiAgent::InternalChat::Responder.respond(message_id: message_id, account_id: account_id)
  end
end
