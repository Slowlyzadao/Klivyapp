module AiAgent
  module Humanization
    # Decides whether the conversation should be handed off to a human BEFORE
    # the LLM gets the next turn. The agent's own TransferToHumanTool covers
    # the case where Bea recognizes mid-reply that she should hand off; this
    # service catches the cases the LLM won't notice on its own:
    #
    #   - sentiment trended negative for 2+ consecutive turns
    #   - the same user message arrived 3+ times in a row (loop, agent stuck)
    #   - tool calls failed twice in a row
    #
    # Returns a Decision struct. Caller (ChatService) checks `escalate?` and,
    # if true, sets the conversation state to escalated and posts a "vou te
    # passar para um atendente" message instead of calling the LLM.
    class EscalationRules
      Decision = Struct.new(:escalate, :reason, keyword_init: true) do
        def escalate? = escalate
      end

      NEGATIVE_THRESHOLD = -0.3
      CONSECUTIVE_NEGATIVE_LIMIT = 2
      CONSECUTIVE_TOOL_FAIL_LIMIT = 2
      # Pacient repeating the same question is normal: WhatsApp resends, our
      # own retries during transient errors, the patient checking if the bot
      # heard them. Only treat as a loop after 5 identical messages — below
      # that we let the LLM try again rather than killing the turn.
      REPEAT_LIMIT = 5

      # Pedido EXPLÍCITO de atendimento humano. Cuidado com falsos
      # positivos do PT-BR coloquial: "a gente" (= "nós") aparece em
      # "a gente consegue?", "a gente vai", etc — não é pedido de
      # humano. Mesmo "alguém" e "pessoa" soltos não bastam ("alguém
      # me explica", "essa pessoa que vinha antes"). Exigimos contexto:
      # palavras fortes (humano/atendente/recepção/robô) sozinhas, OU
      # frases de transferência inequívocas.
      EXPLICIT_HUMAN_REQUEST = Regexp.union(
        /\b(humano|atendente|recep(?:c|ç)(?:ao|ão)|recepcionista)\b/i,
        /\bfalar\s+com\s+(alguém|alguem|uma\s+pessoa|gente\s+de\s+verdade|um\s+humano|uma\s+humana)\b/i,
        /\b(?:pode|poderia|consegue)\s+me\s+(passar|transferir|conectar)\s+(para|pra|com)\s+(alguém|alguem|uma\s+pessoa|um\s+humano)\b/i,
        /\b(?:pode|poderia)\s+chamar\s+(alguém|alguem|uma\s+pessoa)\b/i,
        /\bn[aã]o\s+quero\s+(falar|conversar)\s+com\s+(rob[oô]|bot|m[aá]quina|ia\b)/i,
        /\bcom\s+(uma\s+)?pessoa\s+(de\s+verdade|real)\b/i,
        /\bquero\s+(falar\s+com\s+)?(uma?\s+)?(humano|humana|atendente|recep(?:c|ç)(?:ao|ão)|recepcionista)\b/i
      )
      URGENT_KEYWORDS = /\b(urgent|urgência|emergencia|emergência|sangramento|dor (?:muito|forte|insuport[aá]vel))\b/i

      def initialize(state, last_user_message: nil)
        @state = state
        @msg = last_user_message.to_s
      end

      def evaluate
        return decide('explicit_human_request') if explicit_request?
        return decide('urgent_clinical_signal') if urgent?
        return decide('consecutive_negative_sentiment') if persistent_negative?
        return decide('consecutive_tool_failures') if tool_loop?
        return decide('user_loop') if message_repeated?

        Decision.new(escalate: false, reason: nil)
      end

      private

      def explicit_request?
        @msg.match?(EXPLICIT_HUMAN_REQUEST)
      end

      def urgent?
        @msg.match?(URGENT_KEYWORDS)
      end

      def persistent_negative?
        @state.consecutive_negative_count >= CONSECUTIVE_NEGATIVE_LIMIT
      end

      def tool_loop?
        @state.consecutive_tool_failures >= CONSECUTIVE_TOOL_FAIL_LIMIT
      end

      def message_repeated?
        repeats = @state.working_memory['repeat_count'].to_i
        repeats >= REPEAT_LIMIT
      end

      def decide(reason)
        Decision.new(escalate: true, reason: reason)
      end
    end
  end
end
