# Erro compartilhado pra sinalizar falha PERMANENTE no pipeline telemed
# (Whisper > 25MB, Claude > token cap, formato inválido detectado, etc.).
#
# Jobs devem usar `discard_on Telemed::PermanentFailure` — retentar 3x não
# muda o resultado, só desperdiça download R2 + tokens LLM. Quem raise é
# responsável por mensagem clara; o Job marca `recording.fail!(message)`.
module Telemed
  class PermanentFailure < StandardError; end
end
