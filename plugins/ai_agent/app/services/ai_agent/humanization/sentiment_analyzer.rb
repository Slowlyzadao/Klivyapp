# Cheap-and-fast sentiment classifier. One short LLM call per inbound
# message using whatever fast model is configured globally — no JSON
# mode, just a prompt that demands one of three labels and a score.
#
# Returns a Result struct. Designed to be tolerant: any parsing or
# network failure returns a "neutral / 0.0 / low confidence" Result so
# the caller never has to nil-check.
class AiAgent::Humanization::SentimentAnalyzer
  Result = Struct.new(:label, :score, :confidence, keyword_init: true) do
    def negative?  = label == 'negative'
    def positive?  = label == 'positive'
    def neutral?   = label == 'neutral'
  end

  LABELS = %w[positive neutral negative].freeze
  DEFAULT_RESULT = Result.new(label: 'neutral', score: 0.0, confidence: 0.0).freeze

  def initialize(model: nil)
    @model = model.presence || pick_fast_model
  end

  def call(text)
    return DEFAULT_RESULT if text.to_s.strip.empty?

    ::Llm::Config.initialize!
    chat = RubyLLM.chat(model: @model)
    chat.with_instructions(system_prompt)
    response = chat.ask("Mensagem do paciente: #{text.to_s.strip[0, 1000]}")

    parse(response.content)
  rescue StandardError => e
    Rails.logger.warn("[AiAgent::SentimentAnalyzer] #{e.class}: #{e.message}")
    DEFAULT_RESULT
  end

  private

  def system_prompt
    <<~PROMPT
      Você classifica o SENTIMENTO de uma mensagem de paciente em 3 etiquetas.

      Responda EXATAMENTE no formato (uma única linha, nada mais):
      LABEL=<positive|neutral|negative> SCORE=<-1.0 a 1.0> CONFIDENCE=<0.0 a 1.0>

      - positive: agradecimento, satisfação, animação
      - neutral:  dúvida objetiva, pergunta de info, saudação
      - negative: frustração, raiva, reclamação, dor, urgência

      SCORE: -1.0 muito negativo, 0.0 neutro, +1.0 muito positivo.
      CONFIDENCE: o quanto você está certo, de 0 a 1.
    PROMPT
  end

  def parse(content)
    text = content.to_s.strip
    label_match = text.match(/LABEL=(positive|neutral|negative)/i)
    score_match = text.match(/SCORE=(-?\d+(?:\.\d+)?)/i)
    conf_match  = text.match(/CONFIDENCE=(\d+(?:\.\d+)?)/i)

    return DEFAULT_RESULT unless label_match

    Result.new(
      label: label_match[1].downcase,
      score: clamp(score_match&.[](1).to_f, -1.0, 1.0),
      confidence: clamp(conf_match&.[](1).to_f, 0.0, 1.0)
    )
  end

  def clamp(v, min, max)
    [[v, min].max, max].min
  end

  def pick_fast_model
    provider = InstallationConfig.find_by(name: 'CAPTAIN_LLM_PROVIDER')&.value.to_s
    case provider
    when 'gemini' then InstallationConfig.find_by(name: 'CAPTAIN_GEMINI_MODEL')&.value.presence || 'gemini-3-flash-preview'
    else 'gpt-4.1-nano'
    end
  end
end
