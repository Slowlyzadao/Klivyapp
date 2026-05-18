module AiAgent
  module Formatters
    # Formata nome de profissional pra uso conversacional pela Bea.
    # Convenção: primeiro nome + último sobrenome (sem nomes do meio),
    # padrão brasileiro mais profissional pra apresentação a paciente
    # ("Dra. Claudia Sevegnani" em vez de "Dra. Claudia Raquel Sevegnani").
    #
    # Regras:
    #   1 palavra:   mantém ("João" → "João")
    #   2 palavras:  mantém ("João Silva" → "João Silva")
    #   3+ palavras: primeiro + último ("Claudia Raquel Sevegnani" → "Claudia Sevegnani")
    #
    # Preposições/conectores comuns ("de", "da", "do", "dos", "das", "e")
    # são tratados como parte do sobrenome composto e descartados junto
    # com os nomes do meio:
    #   "Maria das Neves Silva" → "Maria Silva"
    #   "João da Silva Santos"  → "João Santos"
    #
    # A Bea adiciona Dr./Dra. baseada no gênero do nome em PT-BR
    # (responsabilidade do prompt, não desse formatter).
    module ProfessionalName
      def self.format(raw_name)
        return '' if raw_name.to_s.strip.empty?

        parts = raw_name.to_s.strip.split(/\s+/)
        return raw_name.to_s.strip if parts.size <= 2

        "#{parts.first} #{parts.last}"
      end
    end
  end
end
