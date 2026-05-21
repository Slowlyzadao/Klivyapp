# Sprint L — Variante OpenAI (gpt-4o, gpt-4.1, etc) do EvolutionProvider.
#
# Não usada por default no MVP (PRD §5.3 escolheu Claude Sonnet 4.6 por
# qualidade clínica PT-BR). Disponível como fallback rápido caso a chave
# Anthropic não esteja configurada. Reaproveita prompt + parsers do Claude
# via composição — só troca o provider/model na chamada ruby_llm.
require 'ruby_llm'

module Telemed
  module EvolutionProvider
    class OpenAi
      DEFAULT_MODEL = 'gpt-4o'.freeze

      def initialize(model: DEFAULT_MODEL, api_key: nil)
        @model   = model
        @api_key = api_key.presence || lookup_api_key
        @parser  = Claude.new(api_key: 'noop')
      end

      def call(transcript:, patient_context: {})
        raise 'OPENAI_API_KEY ausente' if @api_key.blank?

        context = RubyLLM.context do |config|
          config.openai_api_key = @api_key
          config.logger = Rails.logger
        end

        user_msg = @parser.send(:build_user_message, transcript, patient_context)
        chat = context.chat(model: @model).with_instructions(Claude::SYSTEM_PROMPT)
        response = chat.ask(user_msg)

        markdown = response.content.to_s
        EvolutionProvider::Result.new(
          soap_structure:   @parser.send(:extract_soap_sections, markdown),
          raw_markdown:     markdown,
          attention_points: @parser.send(:extract_attention_points, markdown),
          provider:         "openai/#{@model}",
          input_tokens:     safe_int(response.input_tokens),
          output_tokens:    safe_int(response.output_tokens)
        )
      end

      private

      def lookup_api_key
        InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_API_KEY')&.value ||
          ENV['OPENAI_API_KEY'].presence
      end

      def safe_int(value)
        Integer(value)
      rescue StandardError
        nil
      end
    end
  end
end
