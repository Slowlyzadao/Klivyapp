# Quebra a resposta da Bea em blocos pra enviar como BOLHAS separadas no
# WhatsApp (em vez de um textão único com quebras de linha) — parece mais
# humano. O ChatResponseJob envia cada bloco como uma mensagem, com
# "digitando..." e um wait proporcional ao tamanho do próximo bloco entre eles.
#
# Estratégia de corte: parágrafos (linhas em branco). É como o LLM já
# estrutura a resposta, então cada parágrafo vira uma bolha natural. Limita
# a MAX_CHUNKS pra não metralhar o paciente; o excedente é fundido no último.
class AiAgent::MessageChunker
  MAX_CHUNKS = 4
  CHARS_PER_SECOND = 45.0 # "velocidade de digitação" simulada
  MIN_DELAY = 0.6
  MAX_DELAY = 3.0

  # Retorna um array de blocos (strings não-vazias). Sempre >= 1 elemento.
  def self.split(text)
    parts = text.to_s.split(/\n\s*\n/).map(&:strip).reject(&:empty?)
    return [text.to_s.strip] if parts.size <= 1

    merge_to_max(parts, MAX_CHUNKS)
  end

  # Wait (em segundos) antes de enviar um bloco, proporcional ao tamanho.
  def self.delay_for(chunk)
    (chunk.to_s.length / CHARS_PER_SECOND).clamp(MIN_DELAY, MAX_DELAY)
  end

  # Funde os blocos excedentes no último permitido, preservando a ordem.
  def self.merge_to_max(parts, max)
    return parts if parts.size <= max

    head = parts[0...(max - 1)]
    tail = parts[(max - 1)..].join("\n\n")
    head + [tail]
  end
end
