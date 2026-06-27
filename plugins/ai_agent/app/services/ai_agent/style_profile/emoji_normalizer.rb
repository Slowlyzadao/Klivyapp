# Projeto "Tom de voz da Bea" — normalizador de CADÊNCIA + VARIEDADE de emoji.
#
# Por que existe: medido em produção (gemini-3.5-flash), o prompt NÃO controla
# emoji — o modelo imita o tom caloroso e (a) carimba em quase toda mensagem e
# (b) tende a REPETIR o mesmo emoji (o 🤎), apesar de a clínica usar vários.
# Isto resolve de forma DETERMINÍSTICA na fala final.
#
# PRINCÍPIO (decisão do dono 2026-06-23): NUNCA inserir um emoji que o modelo
# não escolheu — só REMOVER os repetidos/excedentes. Assim cada emoji que sobra
# foi colocado pelo modelo no contexto certo (nada de 🤩 numa frase séria), e a
# variedade vem de tirar a muleta do 🤎 (deixando aparecer os outros que o
# modelo naturalmente usa). Uma tentativa anterior de RODIZIAR pela paleta (
# substituir o emoji) inseria emoji fora de contexto — descartada.
#
# Opera POR PARÁGRAFO (= bolha do WhatsApp; o MessageChunker corta em \n\n),
# carregando estado entre parágrafos e entre turnos (working_memory). Regras:
#   1. no máx 1 emoji por bolha (de-stack — remove o resto);
#   2. um emoji não pode REAPARECER dentro da janela `RECENT` de bolhas com
#      emoji → tira a repetição do 🤎 sem inventar outro no lugar;
#   3. emojis FUNCIONAIS/contextuais (🗓 📍 ✅ …) são preservados (significam
#      algo) e não contam pra regra de repetição;
#   4. no máx `MAX_STREAK` bolhas seguidas com emoji → a próxima sai limpa.
# As PALAVRAS nunca são tocadas — só o emoji.
class AiAgent::StyleProfile::EmojiNormalizer
  EMOJI_RE = /[\p{Extended_Pictographic}\u{FE0F}\u{1F3FB}-\u{1F3FF}\u{200D}\u{20E3}\u{1F1E6}-\u{1F1FF}]/

  # Modificadores/junk que não contam como "um emoji" (tom de pele solto,
  # variation selector, ZWJ, keycap).
  MODIFIER_RE = /[\u{1F3FB}-\u{1F3FF}\u{FE0F}\u{200D}\u{20E3}]/

  # Emojis com SIGNIFICADO contextual — preservados como o modelo escolheu e
  # fora da regra de repetição. Glifos-base (o scan separa o FE0F).
  FUNCTIONAL = %w[📅 🗓 📆 📍 ✅ ✔ ☑ ⏰ ⌚ 📞 ☎ 💳 📋 📄 🔔 ⏳ 📌 🩺 💉 🦷 🏥 ⚠ 🚨].freeze

  MAX_STREAK = 3 # bolhas seguidas com emoji antes de forçar uma limpa
  RECENT = 2     # um emoji não pode reaparecer dentro de N bolhas com emoji

  Result = Struct.new(:text, :state, keyword_init: true)

  # state: { 'recent_emojis' => [String], 'emoji_streak' => Integer } (ou nil)
  def self.call(text:, state: nil)
    new(text, state).call
  end

  def initialize(text, state)
    @text = text.to_s
    st = state.is_a?(Hash) ? state : {}
    @recent = Array(st['recent_emojis']).dup
    @streak = st['emoji_streak'].to_i
  end

  def call
    paras = @text.split(/\n\s*\n/).map(&:rstrip).reject { |p| p.strip.empty? }
    return Result.new(text: @text.strip, state: current_state) if paras.empty?

    out = paras.map { |p| normalize_paragraph(p) }
    Result.new(text: out.join("\n\n"), state: current_state)
  end

  private

  def current_state
    { 'recent_emojis' => @recent.last(RECENT), 'emoji_streak' => @streak }
  end

  def normalize_paragraph(para)
    first = first_emoji(para)
    if first.nil?
      @streak = 0 # bolha sem emoji quebra a sequência
      return para
    end
    # respiro: depois de MAX_STREAK bolhas com emoji, força uma limpa
    if @streak >= MAX_STREAK || drop?(first)
      @streak = 0
      return strip_all(para)
    end

    @recent = (@recent + [first]).last(RECENT)
    @streak += 1
    place_single(para, first)
  end

  # Remove o emoji do modelo quando ele REPETE um usado há pouco (e não é
  # funcional). NUNCA troca por outro — só remove, pra não inserir emoji fora
  # de contexto.
  def drop?(glyph)
    return false if functional?(glyph)

    @recent.include?(glyph)
  end

  def functional?(glyph)
    FUNCTIONAL.include?(glyph)
  end

  # 1º emoji "de verdade" (ignora modificadores soltos).
  def first_emoji(para)
    para.scan(EMOJI_RE).find { |g| !g.match?(MODIFIER_RE) }
  end

  # Mantém só o 1º emoji do modelo; remove todos os outros + junk (de-stack).
  def place_single(para, glyph)
    placed = false
    out = para.gsub(EMOJI_RE) do |g|
      if !placed && !g.match?(MODIFIER_RE)
        placed = true
        glyph
      else
        ''
      end
    end
    tidy(out)
  end

  def strip_all(para)
    tidy(para.gsub(EMOJI_RE, ''))
  end

  # Arruma espaços/quebras que sobram do emoji removido — NÃO mexe nas palavras.
  def tidy(str)
    str.gsub(/[ \t]{2,}/, ' ')
       .gsub(/[ \t]+([\n.,!?])/, '\1')
       .gsub(/\n[ \t]+/, "\n")
       .gsub(/\n{3,}/, "\n\n")
       .strip
  end
end
