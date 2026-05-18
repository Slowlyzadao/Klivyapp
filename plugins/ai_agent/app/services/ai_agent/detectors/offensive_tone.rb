module AiAgent
  module Detectors
    # Classificador determinístico de tom ofensivo/abusivo em mensagens do
    # paciente. Roda em paralelo ao Emergency::Detector (não substitui).
    # Filosofia: thresholds conservadores — pequenas frustrações ("droga",
    # "ai meu deus") não disparam; ofensas diretas, ameaças e palavrões
    # explícitos disparam.
    #
    # Lista de termos privada (não publicar regex). Match retorna o termo
    # detectado pra registro/notificação interna (sem expor outros termos
    # do dicionário).
    class OffensiveTone
      Match = Struct.new(:terms, keyword_init: true)

      # Palavrões diretos endereçados a alguém, ofensas pessoais, ameaças.
      # Word boundary `\b` em todos pra evitar match em palavras compostas
      # legítimas. Lista enxuta — preferimos falso negativo a falso positivo
      # (clínica não quer ser pingada por toda frustração leve).
      OFFENSIVE_PATTERNS = [
        # Ofensa direta
        /\b(?:vai\s+(?:tomar|se\s+f|se\s+lascar|se\s+ferrar|pra)\s+)/i,
        /\bvai\s+se\s+(?:fud|ferrar|lascar|danar)/i,
        /\b(?:filho?\s+da\s+(?:puta|m[aã]e))\b/i,
        /\b(?:vagabund[oa]|escr[oó]ria|vergonha|in[uú]til|imprest[aá]vel)\b/i,
        /\b(?:idiota|imbecil|burr[oa]|otári[oa]|babaca|trouxa|otario)\b/i,
        /\b(?:incompetente|amador(?:a|ona)?|absurd[oa])\b/i,
        /\bm[eé]rda\b(?:\s+de)?\s+(?:cl[ií]nica|atendimento|servi[cç]o|lugar|empresa)/i,
        /\bporr(?:a|ada)\b\s+(?:de|com)\s+(?:cl[ií]nica|atendimento|gente|recep[cç][aã]o)/i,

        # Ameaças
        /\b(?:vou|vamos)\s+(?:processar|denunciar|pegar\s+vcs|acabar\s+com|destruir)/i,
        /\bpr[oó]con\b/i,
        /\breclama[cç][aã]o\s+(?:no|com|na)\s+(?:pr[oó]con|justi[cç]a|conselho)/i,

        # Palavrões direcionados ("seu" + insulto)
        /\bseus?\s+(?:filho|cuz|merda|babaca|otári|imbecil|burr|incompetent)/i
      ].freeze

      # Palavrões soltos contam só se aparecerem 2+ vezes na mesma mensagem
      # (sinaliza intensidade real, não desabafo de uma palavra).
      MILD_PROFANITY = %w[
        caralho porra merda foda fodase fdp puta puto cu cuzao
      ].freeze

      def initialize(message)
        @text = message.to_s
      end

      def call
        terms = OFFENSIVE_PATTERNS.flat_map { |re| @text.scan(re) }.flatten.uniq
        return Match.new(terms: terms.first(5)) if terms.any?

        # Múltiplos palavrões na mesma msg
        downcased = @text.downcase
        mild_count = MILD_PROFANITY.sum { |w| downcased.scan(/\b#{Regexp.escape(w)}\b/).size }
        return Match.new(terms: ["múltiplos palavrões (#{mild_count})"]) if mild_count >= 2

        nil
      end
    end
  end
end
