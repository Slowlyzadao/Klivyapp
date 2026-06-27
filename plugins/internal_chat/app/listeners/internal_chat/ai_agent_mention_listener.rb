module InternalChat
  # Pipeline B (Bea-Chat 2): quando alguém menciona @beatriz no chat interno,
  # despacha pro pipeline de resposta da Bea (assíncrono via Sidekiq).
  #
  # Filtros antes de despachar:
  #   - Só mensagens de humanos disparam (loop guard — Bea ignora outras IAs)
  #   - Só se Bea estiver entre os ai_agent_ids mencionados
  #   - Só se a Bea já existe na conta (BeaResolver)
  #   - Só se o pipeline de resposta interno está disponível (ai_agent loaded)
  #
  # O hook é chamado dentro de InternalChat::MessageDispatcher após a mensagem
  # ser persistida e os mentions registrados.
  class AiAgentMentionListener
    def self.call(message:, ai_agent_ids:)
      return if ai_agent_ids.empty?

      # Loop guard antes do dispatch — não responde a mensagem de IA.
      return if message.sender_ai_agent_id.present?

      bea = InternalChat::BeaResolver.for_account(message.room.account)
      return unless bea
      return unless ai_agent_ids.map(&:to_i).include?(bea.id)

      return unless defined?(::AiAgent::InternalChat::RespondJob)

      # Passa account_id pro job validar tenant — defesa cross-tenant contra
      # jobs forjados com message_id de outra conta.
      ::AiAgent::InternalChat::RespondJob.perform_later(message.id, account_id: message.room.account_id)
    rescue StandardError => e
      Rails.logger.warn("[InternalChat] AiAgentMentionListener falhou: #{e.class}: #{e.message}")
    end
  end
end
