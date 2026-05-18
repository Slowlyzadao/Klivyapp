module AiAgent
  module InternalNotifier
    # Dispara quando AiAgent::Emergency::Detector detecta clinical/suicidal
    # numa mensagem do paciente. Pluga depois do emergency_short_circuit
    # do ChatService — paciente já recebeu a resposta SAMU/CVV templated;
    # agora a equipe precisa saber pra intervir.
    #
    # Categoria do detector mapeia direto pro event_key:
    #   :clinical → clinical_emergency_detected
    #   :suicidal → suicidal_ideation_detected
    #
    # Spec: docs/01-product/ai-agent-configuration-plan.md (Apêndice F)
    class EmergencyAlert
      EVENT_KEYS = {
        clinical: 'clinical_emergency_detected',
        suicidal: 'suicidal_ideation_detected'
      }.freeze

      def self.call(account:, conversation:, contact:, category:, trigger_terms:)
        new(account, conversation, contact, category, trigger_terms).call
      end

      def initialize(account, conversation, contact, category, trigger_terms)
        @account = account
        @conversation = conversation
        @contact = contact
        @category = category.to_sym
        @trigger_terms = trigger_terms
      end

      def call
        event_key = EVENT_KEYS[@category]
        return unless event_key

        AiAgent::InternalNotifier::Dispatcher.dispatch(
          account: @account,
          event_key: event_key,
          vars: build_vars,
          dedupe_key: "#{event_key}:#{@conversation&.id || @contact&.id}:#{Time.current.to_i / 300}"
          # dedupe em janela de 5min — se paciente disparar várias mensagens
          # com keywords seguidas, manda 1 notificação só.
        )
      end

      private

      def build_vars
        {
          patient_name: @contact&.name || 'Paciente sem nome',
          patient_phone: @contact&.phone_number || 'sem telefone',
          trigger_terms: @trigger_terms.to_s.strip[0, 200],
          conversation_link: conversation_link
        }
      end

      def conversation_link
        return '' unless @conversation

        "/app/accounts/#{@account.id}/conversations/#{@conversation.display_id || @conversation.id}"
      end
    end
  end
end
