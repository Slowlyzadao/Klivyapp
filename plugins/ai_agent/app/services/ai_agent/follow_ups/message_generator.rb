require 'ruby_llm'

module AiAgent
  module FollowUps
    # Gera o texto do follow-up usando o LLM leve (mesmo modelo do
    # SentimentAnalyzer/Sentinel — gemini-flash ou gpt-4.1-mini).
    #
    # Recebe:
    #   - rule           — FollowUpRule (traz `context_brief`)
    #   - contact        — Chatwoot Contact
    #   - agenda_event   — AgendaEvent (quando aplicável; nil em no_response)
    #   - patient_memory — PatientMemory (preferences/history pra personalizar)
    #
    # Retorna `String` com a mensagem pronta pra postar — ou `nil` em
    # falha. Caller (SendFollowUpJob) marca execution como `failed` e
    # registra erro.
    #
    # Importante: NÃO usa o ChatService normal porque queremos:
    #   1. Ignorar tools (essa msg é proativa, não deve agendar/cancelar)
    #   2. Persona diferente — atendente proativa, não reativa
    #   3. Custo baixo (modelo flash, 1 turn)
    class MessageGenerator
      MAX_OUTPUT_TOKENS = 220
      DEFAULT_TIMEOUT = 12

      Result = Struct.new(:text, :model, :input_tokens, :output_tokens, keyword_init: true)

      def initialize(rule:, contact:, agenda_event: nil, patient_memory: nil)
        @rule = rule
        @contact = contact
        @agenda_event = agenda_event
        @patient_memory = patient_memory
      end

      def call
        # Garante que RubyLLM tem as keys configuradas. Em workers Sidekiq
        # o initializer do app pode não ter rodado (ou foi resetado). Chamar
        # `initialize!` aqui é idempotente — só configura uma vez por
        # processo, custo zero nas chamadas subsequentes.
        ::Llm::Config.initialize! if defined?(::Llm::Config)

        chat = RubyLLM.chat(model: pick_model, provider: provider_name)
        chat.with_instructions(system_prompt)

        response = chat.ask(user_brief)
        text = response.content.to_s.strip

        return nil if text.empty?

        Result.new(
          text: text,
          model: pick_model,
          input_tokens: response.input_tokens.to_i,
          output_tokens: response.output_tokens.to_i
        )
      rescue StandardError => e
        Rails.logger.warn("[AiAgent::FollowUps::MessageGenerator] rule=#{@rule.id} contact=#{@contact&.id} #{e.class}: #{e.message[0, 200]}")
        nil
      end

      private

      def system_prompt
        # Mantém o tom da Bea consistente com o resto do produto: PT-BR
        # profissional, sem gíria regional, máximo 3 frases, 1 emoji
        # opcional. Reusa a mesma diretiva do CAPTAIN_BEA_SYSTEM_PROMPT
        # para a mensagem ficar com a "voz" da Bea.
        <<~PROMPT.strip
          Você é a Bea, recepcionista virtual da clínica. Está enviando uma
          MENSAGEM PROATIVA pelo WhatsApp (paciente NÃO acabou de mandar
          mensagem — você está iniciando contato baseado num gatilho da
          clínica).

          Tom: profissional, próximo, NEUTRO regionalmente (sem gírias
          paulistas/cariocas — nada de "pô", "tô", "rola", "foi mal",
          "tipo"). Use no máximo 3 frases. Pode usar 1 emoji se fizer
          sentido (✅ confirmação, ❤️ acolhimento). Nunca emoji robótico
          (👋, 🙂, 😊).

          Personalize com o nome do paciente quando disponível. Se houver
          uma consulta envolvida, mencione data, hora e profissional. Se
          o cenário pedir uma resposta do paciente (ex: confirmação),
          deixe a pergunta clara e direta.

          NUNCA invente data, hora, profissional, valor ou dado clínico
          que não esteja no contexto fornecido. Se algo essencial faltar,
          escreva mensagem genérica de check-in.
        PROMPT
      end

      def user_brief
        lines = []
        lines << "Cenário do follow-up: #{@rule.context_brief}"
        lines << ''
        lines << "Nome do paciente: #{@contact.name.to_s.strip.presence || '(não identificado)'}"

        if @agenda_event
          weekday = @agenda_event.starts_at.in_time_zone('America/Sao_Paulo').strftime('%A')
          weekday_pt = weekday_pt_br(weekday)
          lines << "Consulta: #{weekday_pt}, #{@agenda_event.starts_at.in_time_zone('America/Sao_Paulo').strftime('%d/%m %H:%M')}"
          lines << "Profissional: #{@agenda_event.user&.name}" if @agenda_event.user
          lines << "Status atual: #{@agenda_event.status}"
        end

        if @patient_memory
          prefs = @patient_memory.preferences || {}
          lines << "Preferências conhecidas: #{prefs.slice('preferred_time_of_day', 'preferred_professional').to_json}" if prefs.any?
        end

        lines << ''
        lines << 'Escreva agora a mensagem que a Bea vai enviar pelo WhatsApp. Apenas a mensagem, sem explicação, sem prefixo.'
        lines.join("\n")
      end

      def weekday_pt_br(en)
        {
          'Monday' => 'segunda-feira',
          'Tuesday' => 'terça-feira',
          'Wednesday' => 'quarta-feira',
          'Thursday' => 'quinta-feira',
          'Friday' => 'sexta-feira',
          'Saturday' => 'sábado',
          'Sunday' => 'domingo'
        }[en] || en.downcase
      end

      def provider_name
        InstallationConfig.find_by(name: 'CAPTAIN_LLM_PROVIDER')&.value.presence || 'openai'
      end

      def pick_model
        case provider_name
        when 'gemini' then InstallationConfig.find_by(name: 'CAPTAIN_GEMINI_MODEL')&.value.presence || 'gemini-3-flash-preview'
        else InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_MODEL')&.value.presence || 'gpt-4.1-mini'
        end
      end
    end
  end
end
