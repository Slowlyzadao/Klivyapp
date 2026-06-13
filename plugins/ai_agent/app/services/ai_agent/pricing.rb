# Approximate prices per model in USD per 1M tokens, converted to BRL cents
# at a rough fixed rate. The numbers are rounded to give the super admin a
# sense of cost trend — refresh them when the provider changes pricing or
# when USD/BRL drifts more than ~10%.
#
# IMPORTANTE — quando o provedor lança um modelo novo, dois cenários comuns
# geram cálculo zerado/errado se não tratados:
#
#   1. O nome exato do modelo (ex: `gemini-3-flash-preview`) não está na
#      tabela. `lookup` faz match por prefixo pra cobrir variações
#      (`-preview`, `-002`, datas anexadas, etc.).
#
#   2. Tokens vêm zerados pelo wrapper. Esse caso não é resolvido aqui —
#      é responsabilidade do caller capturar `response.input_tokens` /
#      `response.output_tokens` corretamente.
module AiAgent::Pricing
  # USD/BRL aproximado em 2026-05. Atualize se desviar mais que ~10%.
  USD_TO_BRL = 5.5

  # Preços oficiais (USD por 1M tokens, input / output). Conferidos em
  # 2026-05 nas pricing pages da OpenAI e da Google.
  USD_PER_MILLION_TOKENS = {
    # OpenAI
    'gpt-4.1' => { in: 2.0,  out: 8.0  },
    'gpt-4.1-mini' => { in: 0.4,  out: 1.6  },
    'gpt-4.1-nano' => { in: 0.1,  out: 0.4  },
    'gpt-5-mini' => { in: 0.5,  out: 2.0  },
    'gpt-5.1' => { in: 1.5,  out: 6.0  },
    'gpt-5.2' => { in: 3.0,  out: 12.0 },
    'gpt-4o-mini' => { in: 0.15, out: 0.60 },

    # Google Gemini — preço oficial Flash 2.5: $0.30 input, $2.50 output.
    # 1.5 Flash (deprecated) era $0.075/$0.30 — não confundir.
    'gemini-1.5-flash' => { in: 0.075, out: 0.30 },
    'gemini-2.0-flash' => { in: 0.10,  out: 0.40 },
    'gemini-2.5-flash' => { in: 0.30,  out: 2.50 },
    'gemini-2.5-flash-preview' => { in: 0.30,  out: 2.50 },
    'gemini-2.5-pro' => { in: 1.25,  out: 10.0 },
    # Gemini 3 Flash (Preview): preço oficial Google em 2026-05.
    # Input $0.50/M (texto/imagem/vídeo); output $3.00/M (já inclui
    # thinking tokens). Áudio input cobra $1.00/M — não tratado aqui
    # porque a Bea usa Whisper pra áudio, não Gemini.
    'gemini-3-flash' => { in: 0.50,  out: 3.00 },
    'gemini-3-flash-preview' => { in: 0.50,  out: 3.00 },
    # Gemini 3.5 Flash (doc oficial Google, 2026-06): input $1.50/M,
    # output $9.00/M (inclui thinking tokens). NÃO casa por prefixo com
    # 'gemini-3-flash' (é 'gemini-3.5-'), então precisa entrada própria.
    'gemini-3.5-flash' => { in: 1.50,  out: 9.00 },
    'gemini-3-pro' => { in: 2.0,   out: 12.0 },
    'gemini-3-pro-preview' => { in: 2.0,   out: 12.0 },

    # Whisper / áudio (cobrança por segundo, não por token — o caller
    # converte segundos em "tokens equivalentes" antes de chamar)
    'whisper-1' => { in: 0.006, out: 0.0 },

    # Embeddings
    'text-embedding-3-small' => { in: 0.02, out: 0.0 },
    'text-embedding-3-large' => { in: 0.13, out: 0.0 }
  }.freeze

  # Quando nenhum match exato/prefixo funcionar. Conservador alto ($1/$4)
  # pra que modelos desconhecidos APAREÇAM no dashboard como caros e o
  # super admin perceba o gap, em vez de virar zero silencioso.
  DEFAULT = { in: 1.0, out: 4.0 }.freeze

  # Match exato → match por prefixo (ex: "gemini-3-flash-preview-09-2026"
  # bate com "gemini-3-flash-preview" e depois com "gemini-3-flash") →
  # DEFAULT. Garante que sufixos -preview, -002, -09-2026 sigam contando
  # com preço razoável.
  def self.lookup(model)
    key = model.to_s.strip
    return DEFAULT if key.empty?
    return USD_PER_MILLION_TOKENS[key] if USD_PER_MILLION_TOKENS.key?(key)

    candidates = USD_PER_MILLION_TOKENS.keys
                                       .select { |k| key.start_with?(k) }
                                       .sort_by { |k| -k.length }
    return USD_PER_MILLION_TOKENS[candidates.first] if candidates.any?

    DEFAULT
  end

  def self.cost_cents(model:, input_tokens: 0, output_tokens: 0)
    rate = lookup(model)
    usd = ((input_tokens.to_f * rate[:in]) + (output_tokens.to_f * rate[:out])) / 1_000_000.0
    brl = usd * USD_TO_BRL
    (brl * 100).round
  end
end
