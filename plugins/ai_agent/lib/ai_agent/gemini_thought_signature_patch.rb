require 'securerandom'

# Gemini 3 Preview models REQUIRE that every functionCall part returned by
# the model be re-sent back with its `thoughtSignature` field intact in any
# subsequent request that includes that part in the history. Omitting it
# produces 400 BadRequest:
#
#   "Function call is missing a thought_signature in functionCall parts."
#
# The official Python/Node SDKs handle this transparently. RubyLLM 1.9.2
# does not — `extract_tool_calls` drops the signature on the floor and
# `format_tool_call` re-emits the part without it. This patch closes both
# gaps:
#
#   1. `RubyLLM::ToolCall` gains a `thought_signature` accessor.
#   2. Gemini's `extract_tool_calls` populates it from the response part.
#   3. Gemini's `format_tool_call` re-attaches it on outgoing parts.
#
# Reload-safe: re-applying the patch is idempotent, so Rails dev `to_prepare`
# can call this every reload without stacking aliases.
#
# NESTED MODULE INTENTIONAL: este arquivo é `require_relative`'d na
# linha 2 de `engine.rb`, ANTES do Zeitwerk autoload definir `AiAgent`.
# Usar `module AiAgent::GeminiThoughtSignaturePatch` (compact) explode
# com `uninitialized constant AiAgent`. A forma nested define `AiAgent`
# implicitamente — única forma que funciona aqui.
# rubocop:disable Style/ClassAndModuleChildren
module AiAgent
  module GeminiThoughtSignaturePatch
    APPLIED_FLAG = :@__ai_agent_gemini_thought_signature_patched

    def self.apply!
      return unless defined?(::RubyLLM::ToolCall) && defined?(::RubyLLM::Providers::Gemini::Tools)
      return if ::RubyLLM::Providers::Gemini::Tools.instance_variable_get(APPLIED_FLAG)

      patch_tool_call!
      patch_gemini_tools!

      ::RubyLLM::Providers::Gemini::Tools.instance_variable_set(APPLIED_FLAG, true)
    end

    def self.patch_tool_call!
      return if ::RubyLLM::ToolCall.instance_methods.include?(:thought_signature)

      ::RubyLLM::ToolCall.class_eval do
        attr_accessor :thought_signature
      end
    end

    def self.patch_gemini_tools!
      ::RubyLLM::Providers::Gemini::Tools.module_eval do
        # Replaces the upstream method to capture `thoughtSignature` from the
        # response part. Mirrors upstream behavior otherwise — only the two
        # lines marked PATCH are new.
        define_method(:extract_tool_calls) do |data|
          return nil unless data

          candidate = data.is_a?(Hash) ? data.dig('candidates', 0) : nil
          return nil unless candidate

          parts = candidate.dig('content', 'parts')
          return nil unless parts.is_a?(Array)

          tool_calls = parts.each_with_object({}) do |part, result|
            function_data = part['functionCall']
            next unless function_data

            id = SecureRandom.uuid
            tc = ::RubyLLM::ToolCall.new(
              id: id,
              name: function_data['name'],
              arguments: function_data['args'] || {}
            )
            # PATCH: keep the signature alongside the tool call so we can
            # echo it back in the next request.
            sig = part['thoughtSignature']
            tc.thought_signature = sig if sig && !sig.to_s.empty?
            result[id] = tc
          end

          tool_calls.empty? ? nil : tool_calls
        end

        # Replaces the upstream method to attach `thoughtSignature` back on
        # outgoing functionCall parts. Identical otherwise.
        define_method(:format_tool_call) do |msg|
          parts = []

          if msg.content && !(msg.content.respond_to?(:empty?) && msg.content.empty?)
            formatted_content = ::RubyLLM::Providers::Gemini::Media.format_content(msg.content)
            parts.concat(formatted_content.is_a?(Array) ? formatted_content : [formatted_content])
          end

          msg.tool_calls.each_value do |tool_call|
            part = {
              functionCall: {
                name: tool_call.name,
                args: tool_call.arguments
              }
            }
            # PATCH: re-attach thought_signature when present. Gemini 3 rejects
            # the request with 400 BadRequest if missing.
            sig = tool_call.respond_to?(:thought_signature) ? tool_call.thought_signature : nil
            part[:thoughtSignature] = sig if sig && !sig.to_s.empty?
            parts << part
          end

          parts
        end
      end
    end
  end
end
# rubocop:enable Style/ClassAndModuleChildren
