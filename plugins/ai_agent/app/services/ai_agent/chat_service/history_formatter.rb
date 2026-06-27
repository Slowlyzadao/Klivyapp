# Inlines the conversation history into the current user turn instead of
# using `chat.add_message(role: :assistant, ...)` for past replies.
#
# We hit a reproducible RubyLLM + Gemini bug where the model returns an
# empty response (output_tokens=0, no tool call, no error) whenever an
# assistant-role message had been pre-loaded via add_message AND tools
# were attached. Serializing the history as plain text in the user turn
# gives Gemini the same context without tripping the bug.
#
# Extracted from `AiAgent::ChatService#send_with_history` (Fase 4 / BE-1)
# para diminuir o tamanho do orquestrador. Pure function — sem state
# interno. Recebe chat, mensagem, history e prefixo, devolve response.
class AiAgent::ChatService::HistoryFormatter
  # Envia a mensagem do paciente pro chat já com:
  #   - prefixo de contexto (datetime, anchor de serviço, etc.)
  #   - histórico recente serializado como texto plain
  #
  # NOTA: `call` (não `send`) — `Object#send` é built-in e atropelaria
  # a chamada (despacha por método dinâmico em vez de invocar esta).
  #
  # @param chat [RubyLLM::Chat] chat já construído com tools + instructions
  # @param user_message [String] mensagem corrente do paciente
  # @param history [Array<Hash>] lista de {role:, content:} já carregada
  # @param context_prefix [String, nil] prefixo opcional (ContextBuilder.block)
  # @return [RubyLLM::Response]
  def self.call(chat, user_message, history:, context_prefix: nil)
    prefix = context_prefix.to_s.strip
    prefix = prefix.empty? ? '' : "#{prefix}\n\n"

    return chat.ask("#{prefix}#{user_message}") if history.empty?

    preamble = history.map do |msg|
      speaker = msg[:role].to_s == 'user' ? 'Paciente' : 'Você (Bea)'
      "#{speaker}: #{msg[:content]}"
    end.join("\n")
    chat.ask("#{prefix}Histórico recente desta conversa:\n#{preamble}\n\nNova mensagem do paciente: #{user_message}")
  end
end
