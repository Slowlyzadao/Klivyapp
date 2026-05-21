# Sprint L — EvolutionProvider Claude (ruby_llm + Anthropic).
#
# Modelo padrão: `claude-sonnet-4-6` (id ruby_llm). Render SOAP em PT-BR.
# Resposta esperada: bloco markdown com sections `## S — Subjetivo`, etc,
# seguido de bloco JSON com attention_points pra parse estruturado.
#
# Prompt projetado pra:
#   - rejeitar conteúdo fora de escopo clínico (transcript social/fora-pauta)
#   - explicitar incerteza ("se incerto, deixe em branco")
#   - destacar contraindicações, alergias, medicações em curso
require 'ruby_llm'

module Telemed
  module EvolutionProvider
    class Claude
      DEFAULT_MODEL = 'claude-sonnet-4-6'.freeze
      SYSTEM_PROMPT = <<~PROMPT
        Você é um assistente clínico especializado em odontologia, escrevendo em
        português brasileiro. Sua tarefa é estruturar uma evolução clínica no
        formato SOAP (Subjetivo / Objetivo / Avaliação / Plano) a partir de uma
        transcrição de teleconsulta entre Doutor(a) e Paciente.

        Regras OBRIGATÓRIAS:
        - Use vocabulário clínico preciso, mas claro.
        - NÃO invente sintomas ou achados que não estejam na transcrição.
        - Se algum bloco (S/O/A/P) não tiver informação suficiente, escreva
          "(Sem informação suficiente na consulta — verificar presencialmente)".
        - Cite trechos relevantes da fala do paciente entre aspas quando útil.
        - Sinalize PONTOS DE ATENÇÃO ao final (alergias, contraindicações,
          interações medicamentosas, contexto sistêmico relevante).

        Formato de saída — siga EXATAMENTE este template:

        ## S — Subjetivo
        (texto)

        ## O — Objetivo
        (texto)

        ## A — Avaliação
        (texto)

        ## P — Plano
        (texto)

        ## Pontos de Atenção (JSON)
        ```json
        [
          {"type":"alergy|medication|systemic|behavior|other","severity":"low|medium|high","text":"..."}
        ]
        ```
      PROMPT

      def initialize(model: DEFAULT_MODEL, api_key: nil)
        @model   = model
        @api_key = api_key.presence || lookup_api_key
      end

      # `transcript` é a string formatada do TranscribeRecordingJob.
      # `patient_context` é hash com alergias, medicações, histórico breve.
      def call(transcript:, patient_context: {})
        raise 'ANTHROPIC_API_KEY ausente — não é possível gerar evolução' if @api_key.blank?

        user_content = build_user_message(transcript, patient_context)

        context = RubyLLM.context do |config|
          config.anthropic_api_key = @api_key
          config.logger = Rails.logger
        end

        chat = context.chat(model: @model).with_instructions(SYSTEM_PROMPT)
        response = chat.ask(user_content)

        markdown = response.content.to_s
        parse_response(markdown, response)
      end

      private

      def build_user_message(transcript, patient_context)
        ctx = patient_context.is_a?(Hash) ? patient_context : {}
        ctx_lines = [
          "Nome do paciente: #{ctx[:name] || 'não informado'}",
          "Idade: #{ctx[:age] || 'não informada'}",
          "Alergias conhecidas: #{Array(ctx[:allergies]).join(', ').presence || 'nenhuma registrada'}",
          "Medicações em curso: #{Array(ctx[:medications]).join(', ').presence || 'nenhuma registrada'}",
          "Histórico relevante: #{ctx[:history] || 'sem registro'}"
        ]

        <<~MSG
          ### Contexto do paciente
          #{ctx_lines.join("\n")}

          ### Transcrição da teleconsulta
          #{transcript}

          ### Tarefa
          Gere a evolução SOAP no formato especificado.
        MSG
      end

      def parse_response(markdown, response)
        soap = extract_soap_sections(markdown)
        attention = extract_attention_points(markdown)

        EvolutionProvider::Result.new(
          soap_structure:   soap,
          raw_markdown:     markdown,
          attention_points: attention,
          provider:         "claude/#{@model}",
          input_tokens:     safe_int(response.input_tokens),
          output_tokens:    safe_int(response.output_tokens)
        )
      end

      # Heurística simples — Claude segue o template, então split por `## `.
      # Mantemos o fallback robusto: se não casar, deixamos as chaves vazias
      # e o caller exibe `raw_markdown` pra revisão manual.
      SECTION_KEYS = {
        /^##\s*S\b/i => 'subjetivo',
        /^##\s*O\b/i => 'objetivo',
        /^##\s*A\b/i => 'avaliacao',
        /^##\s*P\b/i => 'plano'
      }.freeze

      def extract_soap_sections(markdown)
        lines = markdown.lines
        current_key = nil
        buckets = { 'subjetivo' => [], 'objetivo' => [], 'avaliacao' => [], 'plano' => [] }

        lines.each do |line|
          matched_key = SECTION_KEYS.find { |regex, _| line =~ regex }
          if matched_key
            current_key = matched_key.last
            next
          end
          # Para na seção de Pontos de Atenção — não faz parte do SOAP.
          break if line =~ /^##\s*Pontos\s*de\s*Aten/i

          buckets[current_key] << line if current_key && buckets[current_key]
        end

        buckets.transform_values { |arr| arr.join.strip }
      end

      def extract_attention_points(markdown)
        json_block = markdown[/```json\s*(.*?)\s*```/m, 1]
        return [] if json_block.blank?

        parsed = JSON.parse(json_block)
        return [] unless parsed.is_a?(Array)

        parsed.map do |point|
          next unless point.is_a?(Hash)
          {
            'type'     => point['type'].to_s.presence || 'other',
            'severity' => point['severity'].to_s.presence || 'medium',
            'text'     => point['text'].to_s
          }
        end.compact
      rescue JSON::ParserError
        [] # caller mantém raw_markdown — humano vê tudo.
      end

      def lookup_api_key
        ENV['ANTHROPIC_API_KEY'].presence ||
          InstallationConfig.find_by(name: 'ANTHROPIC_API_KEY')&.value
      end

      def safe_int(value)
        Integer(value)
      rescue StandardError
        nil
      end
    end
  end
end
