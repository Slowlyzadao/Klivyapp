module AiAgent
  module InternalNotifier
    # Notifica equipe quando OffensiveTone detector pega tom hostil/agressivo
    # numa mensagem do paciente. Bea continua respondendo normalmente — o
    # objetivo aqui é dar visibilidade pra equipe poder intervir, não
    # silenciar a Bea.
    #
    # Dedupe por janela de 30min: se o paciente continua hostil em sequência,
    # equipe recebe 1 alerta a cada meia hora (não inunda).
    #
    # Spec: docs/01-product/ai-agent-configuration-plan.md (Apêndice F)
    class OffensiveToneAlert
      EVENT_KEY = 'offensive_patient_tone'.freeze

      def self.call(account:, conversation:, contact:, terms:)
        new(account, conversation, contact, terms).call
      end

      def initialize(account, conversation, contact, terms)
        @account = account
        @conversation = conversation
        @contact = contact
        @terms = Array(terms)
      end

      def call
        AiAgent::InternalNotifier::Dispatcher.dispatch(
          account: @account,
          event_key: EVENT_KEY,
          vars: build_vars,
          dedupe_key: "#{EVENT_KEY}:#{@conversation&.id || @contact&.id}:#{Time.current.to_i / 1800}"
        )
      end

      private

      def build_vars
        {
          patient_name: @contact&.name || 'Paciente sem nome',
          patient_phone: @contact&.phone_number || 'sem telefone',
          trigger_terms: @terms.join(', ').to_s[0, 200],
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
