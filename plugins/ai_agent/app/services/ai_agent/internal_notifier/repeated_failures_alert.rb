module AiAgent
  module InternalNotifier
    # Notifica equipe quando a Bea respondeu evasivamente 3+ vezes seguidas
    # ao mesmo paciente. Sinal de lacuna na base de conhecimento — equipe
    # vai querer adicionar info que está faltando.
    #
    # Estado vive em `ConversationState.working_memory['evasive']`:
    #   { 'count' => N, 'topics' => ["…"], 'last_at' => iso8601 }
    #
    # Reseta o contador após disparar (evita spam — equipe é pingada UMA
    # vez quando atinge o limite, não em toda mensagem evasiva subsequente).
    class RepeatedFailuresAlert
      EVENT_KEY = 'bea_repeated_failures'.freeze
      THRESHOLD = 3
      TOPIC_WINDOW = 60.minutes

      def self.track(state:, last_user_message:, conversation:, contact:, account:)
        new(state, last_user_message, conversation, contact, account).track
      end

      def initialize(state, last_user_message, conversation, contact, account)
        @state = state
        @last_user_message = last_user_message.to_s
        @conversation = conversation
        @contact = contact
        @account = account
      end

      def track
        memory = (@state.working_memory || {}).deep_dup
        evasive = memory['evasive'] || { 'count' => 0, 'topics' => [], 'last_at' => nil }

        # Reset se a última evasiva foi há mais de TOPIC_WINDOW (paciente já
        # mudou de assunto há tempo — não soma com episódio antigo)
        if evasive['last_at']
          last_at = Time.zone.parse(evasive['last_at']) rescue nil
          evasive = { 'count' => 0, 'topics' => [], 'last_at' => nil } if last_at && last_at < TOPIC_WINDOW.ago
        end

        evasive['count'] = evasive['count'].to_i + 1
        evasive['topics'] = (evasive['topics'] + [topic_from_message]).uniq.last(5)
        evasive['last_at'] = Time.current.iso8601

        if evasive['count'] >= THRESHOLD
          dispatch_alert(evasive)
          evasive = { 'count' => 0, 'topics' => [], 'last_at' => nil }
        end

        memory['evasive'] = evasive
        @state.update!(working_memory: memory)
      end

      private

      def topic_from_message
        # Extrai trecho-chave da última pergunta do paciente — primeiras
        # ~80 chars, sem quebras. Heurística simples: o assunto que a Bea
        # não soube responder geralmente está NA PERGUNTA, não na resposta.
        @last_user_message.gsub(/\s+/, ' ').strip[0, 80]
      end

      def dispatch_alert(evasive)
        AiAgent::InternalNotifier::Dispatcher.dispatch(
          account: @account,
          event_key: EVENT_KEY,
          vars: build_vars(evasive),
          dedupe_key: "#{EVENT_KEY}:#{@conversation&.id || @contact&.id}:#{Time.current.to_i / 3600}"
        )
      end

      def build_vars(evasive)
        {
          patient_name: @contact&.name || 'Paciente sem nome',
          patient_phone: @contact&.phone_number || 'sem telefone',
          failure_count: evasive['count'].to_s,
          topics: evasive['topics'].join(' · '),
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
