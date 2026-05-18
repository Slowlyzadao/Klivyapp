module AiAgent
  module Memory
    # Roda 1 LLM leve sobre histórico + últimas mensagens do paciente e
    # destila num perfil semântico estruturado. Usado pelo
    # ConsolidatePatientMemoryJob (cron noturno) — NÃO entra no caminho
    # síncrono de resposta da Bea.
    #
    # Falha tolerante: qualquer erro retorna nil e o caller pula a
    # consolidação desse paciente — perfil antigo segue válido.
    class Distiller
      Result = Struct.new(:profile, :raw, keyword_init: true)

      MAX_HISTORY = 30          # entries do PatientMemory.history
      MAX_MESSAGES = 30         # mensagens recentes (cross-conversation)
      MAX_MESSAGE_CHARS = 200   # cada mensagem truncada
      WINDOW_DAYS = 90          # mensagens das últimas N dias só

      # Keys que o perfil retornado pode ter. Tudo opcional —
      # campos ausentes do output do LLM ficam nil.
      PROFILE_KEYS = %w[
        preferred_time_of_day
        preferred_professional
        frequent_services
        tone
        health_notes
        summary
      ].freeze

      def initialize(memory:, model: nil)
        @memory = memory
        @model = model.presence || pick_fast_model
      end

      def call
        history_block = build_history_block
        messages_block = build_messages_block
        return nil if history_block.blank? && messages_block.blank?

        ::Llm::Config.initialize!
        chat = RubyLLM.chat(model: @model)
        chat.with_instructions(system_prompt)

        prompt = "HISTÓRICO ESTRUTURADO:\n#{history_block.presence || '(vazio)'}\n\nMENSAGENS RECENTES:\n#{messages_block.presence || '(vazio)'}"
        response = chat.ask(prompt)

        profile = parse(response.content)
        return nil if profile.nil?

        Result.new(profile: profile, raw: response.content.to_s[0, 2000])
      rescue StandardError => e
        Rails.logger.warn("[AiAgent::Memory::Distiller] memory=#{@memory.id} #{e.class}: #{e.message}")
        nil
      end

      private

      def system_prompt
        <<~PROMPT
          Você lê histórico + mensagens de um paciente de uma clínica e
          extrai um PERFIL SEMÂNTICO compacto pra ajudar a Bea (assistente
          virtual) a personalizar futuras conversas.

          Responda APENAS um objeto JSON válido (nada antes nem depois),
          com estas chaves (todas opcionais — omita o que não tiver
          evidência clara no histórico, JAMAIS invente):

          {
            "preferred_time_of_day": "manhã" | "tarde" | "noite" | "qualquer",
            "preferred_professional": "<nome OU null>",
            "frequent_services": ["<até 3 serviços mais comuns>"],
            "tone": "formal" | "informal" | "direto" | "chatty",
            "health_notes": ["<alergias / condições crônicas mencionadas, sem diagnósticos novos>"],
            "summary": "<1-2 frases sobre quem é esse paciente do ponto de vista de atendimento>"
          }

          Regras:
          - Não inclua diagnósticos clínicos. Apenas registre o que o paciente
            já declarou (alergia, condição crônica conhecida).
          - Não inclua dados sensíveis fora desse escopo (financeiro,
            relacionamentos, religião, política).
          - Se o histórico está vazio ou não há sinal forte de preferência,
            retorne `{}`.
          - JSON puro. Sem markdown, sem texto antes ou depois.
        PROMPT
      end

      def build_history_block
        entries = Array(@memory.history).last(MAX_HISTORY)
        return '' if entries.empty?

        entries.map do |h|
          at = h['at'].to_s
          type = h['type'].to_s
          summary = h['summary'].to_s.strip
          "  - [#{at}] #{type}: #{summary}"
        end.join("\n")
      end

      # Mensagens cross-conversation do paciente nas últimas WINDOW_DAYS
      # dias. Reusa a tabela de Messages do Chatwoot (sem state nosso).
      def build_messages_block
        cutoff = WINDOW_DAYS.days.ago

        scope = ::Message.joins(:conversation)
                         .where(conversations: { contact_id: @memory.contact_id, account_id: @memory.account_id })
                         .where(message_type: %i[incoming outgoing])
                         .where(private: false)
                         .where('messages.created_at >= ?', cutoff)
                         .order('messages.created_at DESC')
                         .limit(MAX_MESSAGES)

        rows = scope.to_a.reverse
        return '' if rows.empty?

        rows.map do |m|
          speaker = m.incoming? ? 'Paciente' : 'Bea'
          content = m.content.to_s.strip[0, MAX_MESSAGE_CHARS]
          "  #{speaker}: #{content}"
        end.join("\n")
      end

      def parse(content)
        text = content.to_s.strip

        # Tolera ```json fences se o modelo escapou
        text = text.sub(/\A```(?:json)?\s*/i, '').sub(/```\s*\z/i, '').strip

        json_start = text.index('{')
        json_end = text.rindex('}')
        return nil if json_start.nil? || json_end.nil? || json_end < json_start

        parsed = JSON.parse(text[json_start..json_end])
        return nil unless parsed.is_a?(Hash)

        # Pick only allowed keys, normalize tipos.
        profile = {}
        PROFILE_KEYS.each do |k|
          v = parsed[k]
          next if v.nil?

          case k
          when 'frequent_services', 'health_notes'
            arr = Array(v).map { |x| x.to_s.strip }.reject(&:empty?).first(5)
            profile[k] = arr if arr.any?
          when 'preferred_professional'
            profile[k] = v.to_s.strip[0, 100] if v.to_s.strip.present?
          when 'summary'
            profile[k] = v.to_s.strip[0, 400] if v.to_s.strip.present?
          else
            profile[k] = v.to_s.strip if v.to_s.strip.present?
          end
        end

        profile
      rescue JSON::ParserError, StandardError => e
        Rails.logger.warn("[AiAgent::Memory::Distiller] parse falhou: #{e.message[0, 200]}")
        nil
      end

      def pick_fast_model
        provider = InstallationConfig.find_by(name: 'CAPTAIN_LLM_PROVIDER')&.value.to_s
        case provider
        when 'gemini' then InstallationConfig.find_by(name: 'CAPTAIN_GEMINI_MODEL')&.value.presence || 'gemini-3-flash-preview'
        else 'gpt-4.1-mini'
        end
      end
    end
  end
end
