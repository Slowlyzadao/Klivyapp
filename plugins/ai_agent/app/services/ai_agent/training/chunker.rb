# Estágio 3 — Blocagem inteligente (anti-alucinação). Divide a conversa
# transcrita em blocos para o modelo de extração, respeitando fronteiras de
# turno: cada mensagem é atômica (nunca cortada) e um bloco só fecha após uma
# fala da CLÍNICA — fechando, de preferência, um par pergunta→resposta. Há
# sobreposição de 1 mensagem entre blocos pra não perder contexto na emenda.
class AiAgent::Training::Chunker
  Block = Struct.new(:text, :message_count, keyword_init: true)

  TARGET_CHARS = 8_000 # ~2k tokens
  OVERLAP_MESSAGES = 1

  def self.call(messages:, target_chars: TARGET_CHARS)
    new(messages, target_chars).call
  end

  def initialize(messages, target_chars)
    @messages = messages.select { |msg| msg.text.to_s.strip.present? }
    @target_chars = target_chars
  end

  def call
    blocks = []
    current = []
    chars = 0

    @messages.each do |msg|
      current << msg
      chars += line_for(msg).length + 1

      next unless chars >= @target_chars && clinic?(msg)

      blocks << build(current)
      current = current.last(OVERLAP_MESSAGES)
      chars = current.sum { |msg_in_overlap| line_for(msg_in_overlap).length + 1 }
    end

    blocks << build(current) if current.any?
    blocks
  end

  private

  def build(messages)
    Block.new(
      text: messages.map { |msg| line_for(msg) }.join("\n"),
      message_count: messages.size
    )
  end

  def line_for(msg)
    "#{msg.role}: #{msg.text}"
  end

  def clinic?(msg)
    msg.role == AiAgent::Training::ChatParser::ROLE_CLINIC
  end
end
