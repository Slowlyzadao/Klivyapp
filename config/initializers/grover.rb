# frozen_string_literal: true

# Config global do Grover (HTML→PDF via Chromium headless), usado pelo plugin
# document_templates e, indiretamente, pelo signatures (quando o signable é
# renderizado a partir de `rendered_html`).
#
# Por que este initializer existe:
#   - O container roda como root; o Chromium headless recusa subir como root
#     sem `--no-sandbox`. Sem esta flag, TODA geração de PDF falha.
#   - `--disable-dev-shm-usage` evita crash do Chrome quando `/dev/shm` é pequeno
#     (padrão em containers) — passa a usar `/tmp`.
#   - O binário do Chromium vem do apt via `PUPPETEER_EXECUTABLE_PATH`
#     (definido em docker/dockerfiles/rails.Dockerfile como /usr/bin/chromium),
#     em vez do download do puppeteer: `/app/node_modules` é volume nomeado em
#     dev, então o Chrome baixado lá não persistiria.
#
# As opções por-documento (format/margin/timeout) continuam em
# `DocumentTemplates::PdfGenerator#html_to_pdf`; o Grover faz merge com estas.
Grover.configure do |config|
  config.options = {
    launch_args: ['--no-sandbox', '--disable-dev-shm-usage']
  }
end
