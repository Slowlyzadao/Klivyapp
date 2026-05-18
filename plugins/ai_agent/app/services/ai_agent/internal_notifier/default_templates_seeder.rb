module AiAgent
  module InternalNotifier
    # Garante que cada Account tenha 1 InternalNotificationTemplate por event_key
    # do EventCatalog. Idempotente — só cria os que faltam, não toca nos
    # existentes (preserva customizações da clínica).
    #
    # Templates nascem DESATIVADOS (target_type='disabled'). A clínica
    # configura o destino (sala/DM) na UI BEA → Templates depois de criar
    # os grupos relevantes no Chat Interno.
    #
    # Spec: docs/01-product/ai-agent-configuration-plan.md (Apêndice F)
    class DefaultTemplatesSeeder
      def self.seed_for_account(account)
        new(account).seed
      end

      def initialize(account)
        @account = account
      end

      def seed
        AiAgent::InternalNotifier::EventCatalog::EVENTS.each do |event_key, meta|
          next if AiAgent::InternalNotificationTemplate.exists?(account_id: @account.id, event_key: event_key)

          AiAgent::InternalNotificationTemplate.create!(
            account_id: @account.id,
            event_key: event_key,
            name: meta[:label],
            body: meta[:default_body].to_s.strip,
            target_type: 'disabled',
            target_id: nil,
            enabled: false
          )
        end
      end
    end
  end
end
