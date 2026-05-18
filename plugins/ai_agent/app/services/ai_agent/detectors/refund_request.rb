module AiAgent
  module Detectors
    # Detecta menção a estorno, reembolso ou contestação financeira na
    # mensagem do paciente. Determinístico — palavras-chave bem específicas
    # do contexto financeiro (sem captura de "devolver" genérico).
    #
    # Conservador por padrão: prefere falso negativo a falso positivo.
    # Equipe financeira não quer ser pingada por "esqueci a chave".
    class RefundRequest
      Match = Struct.new(:terms, :summary, keyword_init: true)

      PATTERNS = [
        # Estorno / reembolso
        /\b(?:quero|preciso\s+de|posso\s+pedir\s+um?|gostaria\s+de\s+um?)\s+estorno\b/i,
        /\bestornar\s+(?:o|a|esse|essa|meu|minha)/i,
        /\b(?:quero|preciso|gostaria|pode\s+(?:fazer|me\s+dar))\s+(?:meu\s+|o\s+)?reembolso\b/i,
        /\breembolsar\s+(?:o|a|esse|essa|meu|minha)/i,
        /\b(?:devolver|devolu[cç][aã]o\s+do?)\s+(?:dinheiro|valor|pagamento|pix)/i,
        /\bressarcimento\b/i,

        # Contestação de cobrança
        /\bcontestar?\s+(?:a|essa|esta|uma)?\s*cobran[cç]a/i,
        /\bcobran[cç]a\s+(?:indevida|errada|duplicada|duplicad|incorreta)\b/i,
        /\bcobran[cç]a\s+(?:est[aá]\s+|t[aá]\s+)?indevida\b/i,
        /\bn[aã]o\s+(?:reconhe[cç]o|fui\s+eu)\s+(?:essa|esta)\s+cobran[cç]a\b/i,
        /\b(?:cobraram|fui\s+cobrad[oa])\s+(?:errado|2\s+vezes|duas\s+vezes|duplicado|a\s+mais|em\s+duplicidade)\b/i,
        /\b(?:cobrad[oa]|cobraram)\s+(?:em\s+)?(?:2|duas|3|tr[eê]s)\s+vezes\b/i,

        # Cancelamento de pagamento
        /\bcancelar\s+(?:o|esse|esta|essa|meu|minha)\s+(?:pagamento|cobran[cç]a|d[eé]bito|boleto)/i,
        /\bchargeback\b/i,
        /\bdisputar?\s+(?:no|essa|a)\s+(?:cart[aã]o|cobran[cç]a)/i
      ].freeze

      def initialize(message)
        @text = message.to_s
      end

      def call
        terms = PATTERNS.flat_map { |re| @text.scan(re) }.flatten.uniq
        return nil if terms.empty?

        Match.new(
          terms: terms.first(5),
          summary: @text.strip[0, 200]
        )
      end
    end
  end
end
