module InternalChat
  # Resolve a "identidade da Bea" para uma conta. Hoje a Bea é representada
  # pela Captain::Assistant chamada "Beatriz" (configuração protegida em
  # /super_admin/bea). O id que guardamos em `ai_agent_id` (memberships e
  # messages) é o id dessa Assistant.
  #
  # Sprint 7 só faz a fundação: identificar a Bea, permitir membership e
  # mentions. O comportamento (Bea responder no chat) entra em sprint futuro.
  class BeaResolver
    DEFAULT_NAME = 'Beatriz'.freeze
    DISPLAY_LABEL = 'Beatriz · IA'.freeze

    def self.for_account(account)
      return nil unless defined?(::Captain::Assistant)

      ::Captain::Assistant.find_by(account_id: account.id, name: DEFAULT_NAME)
    end

    def self.payload_for(account)
      bea = for_account(account)
      return nil unless bea

      {
        ai_agent_id: bea.id,
        name: DISPLAY_LABEL,
        avatar_url: nil,
        is_ai: true,
      }
    end
  end
end
