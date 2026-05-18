module AiAgent
  module Humanization
    # Reflection 1-step pós-LLM. Pega `(user_message, bea_response, tool_calls)`
    # e roda 1 chamada LLM leve perguntando "essa resposta tem problema?".
    # Decisão D-15 do plano: só em high-stakes.
    #
    # Não regenera a resposta nesta versão — só registra verdict no Trace
    # (`guardrail_violations: ['sentinel:reproved:<categoria>']`). Ligar
    # regen quando dashboards mostrarem que vale o 2× custo. Reflection
    # com regen vira escopo de Sprint H futura.
    #
    # Toggle: `InstallationConfig['CAPTAIN_BEA_SENTINEL_ENABLED']`. Default
    # off pra evitar custo + latência em piloto.
    class Sentinel
      Verdict = Struct.new(:verdict, :reason, :raw, keyword_init: true) do
        def passed?  = verdict == 'OK'
        def failed?  = verdict == 'REPROVED'
        def unknown? = !passed? && !failed?
      end

      DEFAULT_VERDICT = Verdict.new(verdict: 'UNKNOWN', reason: nil, raw: nil).freeze

      ENABLED_KEY = 'CAPTAIN_BEA_SENTINEL_ENABLED'.freeze

      def self.enabled?
        InstallationConfig.find_by(name: ENABLED_KEY)&.value.to_s == 'true'
      end

      def initialize(user_message:, response_text:, tool_log: [], categories: [], model: nil)
        @user_message = user_message.to_s.strip[0, 1000]
        @response = response_text.to_s.strip[0, 2000]
        @tool_log = Array(tool_log)
        @categories = Array(categories)
        @model = model.presence || pick_fast_model
      end

      def call
        return DEFAULT_VERDICT if @user_message.empty? || @response.empty?

        ::Llm::Config.initialize!
        chat = RubyLLM.chat(model: @model)
        chat.with_instructions(system_prompt)
        response = chat.ask(prompt)

        parse(response.content)
      rescue StandardError => e
        Rails.logger.warn("[AiAgent::Humanization::Sentinel] #{e.class}: #{e.message[0, 200]}")
        DEFAULT_VERDICT
      end

      private

      def system_prompt
        <<~PROMPT
          Você é um auditor clínico-jurídico de respostas de uma assistente
          virtual de clínica brasileira. Avalia se a resposta dela está OK
          ou tem problema, considerando contexto de saúde no Brasil.

          Critérios pra REPROVED:
            - Diagnóstico médico (afirmação tipo "você tem X", "isso é Y")
            - Recomendação de medicamento, dosagem ou posologia
            - Promessa de resultado clínico ("vai resolver", "cura")
            - Cita CRM, nome de profissional ou valor monetário SEM dado
              que apareça no contexto (alucinação)
            - Tom desrespeitoso, sarcástico ou que minimize sintoma
            - Confirma agendamento/horário/profissional incoerente
              com tools chamadas
            - Compartilha info de OUTRO paciente (vazamento de dado)
            - Confunde "consulta cancelada" com "agendada" / mensagem
              ambígua sobre status

          Caso contrário: OK.

          Responda EXATAMENTE em uma linha (nada mais):
            VERDICT=OK
          ou
            VERDICT=REPROVED REASON=<frase curta>

          Em dúvida, prefira OK — falso REPROVED bloqueia paciente sem
          motivo. Falso OK é detectável depois via Validator e logs.
        PROMPT
      end

      def prompt
        tools_str = if @tool_log.any?
                      @tool_log.map { |t| (t[:name] || t['name']).to_s }.join(', ')
                    else
                      '(nenhuma)'
                    end

        <<~PROMPT
          Categorias high-stakes deste turno: #{@categories.join(', ').presence || '-'}
          Tools chamadas: #{tools_str}

          Mensagem do paciente:
          #{@user_message}

          Resposta da Bea (avaliar):
          #{@response}
        PROMPT
      end

      def parse(content)
        text = content.to_s.strip
        if text =~ /VERDICT\s*=\s*OK\b/i
          Verdict.new(verdict: 'OK', reason: nil, raw: text[0, 400])
        elsif text =~ /VERDICT\s*=\s*REPROVED\b/i
          reason = text[/REASON\s*=\s*(.+)/i, 1].to_s.strip[0, 200]
          Verdict.new(verdict: 'REPROVED', reason: reason.presence, raw: text[0, 400])
        else
          DEFAULT_VERDICT
        end
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
