require 'open3'

# Estágio 2 — Transcrição de áudio. Para cada mensagem de áudio, localiza o
# `.opus` pelo nome, aplica denoise via ffmpeg (mata a alucinação do Whisper
# em silêncio/ruído) e transcreve via OpenAI `gpt-4o-transcribe` — o mesmo
# caminho já comprovado em `plugins/telemed`. A transcrição substitui o texto
# da mensagem, marcada como `[ÁUDIO]: …`, preservando papel e posição.
#
# Degradação graciosa: áudio sem arquivo, grande demais ou que falhe na
# transcrição vira `[ÁUDIO NÃO TRANSCRITO]` — nunca derruba o pipeline.
class AiAgent::Training::AudioTranscriber
  MODEL = ENV.fetch('AI_AGENT_TRANSCRIBE_MODEL', 'gpt-4o-transcribe')
  LANGUAGE = 'pt'.freeze
  MAX_BYTES = 25 * 1024 * 1024 # limite da API de transcrição
  REQUEST_TIMEOUT = 180

  PREFIX = '[ÁUDIO]: '.freeze
  FAILED = '[ÁUDIO NÃO TRANSCRITO]'.freeze

  # messages:    Array<ChatParser::Message> (mutadas in-place)
  # audio_files: Array<{ name:, path: }>
  # on_progress: callable opcional, recebe o nº de áudios já processados
  def self.call(messages:, audio_files:, on_progress: nil)
    new(messages, audio_files, on_progress).call
  end

  def initialize(messages, audio_files, on_progress)
    @messages = messages
    @audio_by_name = audio_files.index_by { |audio| audio[:name] }
    @on_progress = on_progress
  end

  def call
    done = 0
    @messages.each do |msg|
      next unless msg.type == AiAgent::Training::ChatParser::TYPE_AUDIO

      audio = @audio_by_name[msg.attachment]
      msg.text = audio ? transcribe(audio[:path]) : FAILED
      done += 1
      @on_progress&.call(done)
    end
    @messages
  end

  private

  def transcribe(path)
    cleaned = denoise(path)
    source = cleaned || path
    return FAILED if File.size(source) > MAX_BYTES

    text = request_transcription(source)
    return FAILED if text.blank?

    # O ChatParser mascara PII quando o texto do áudio ainda é vazio — a
    # transcrição chega DEPOIS, então a redação (LGPD) precisa acontecer aqui:
    # CPF/telefone falados num áudio não podem sobrar no texto persistido.
    "#{PREFIX}#{AiAgent::Training::PiiRedactor.call(text.strip)}"
  rescue StandardError => e
    Rails.logger.warn("[AiAgent::Training::AudioTranscriber] #{File.basename(path)}: #{e.class}: #{e.message}")
    FAILED
  ensure
    File.delete(cleaned) if cleaned && File.exist?(cleaned)
  end

  # Denoise + mono via ffmpeg antes do Whisper (highpass remove rumble,
  # afftdn corta ruído estacionário, dynaudnorm normaliza). Retorna o caminho
  # do arquivo limpo, ou nil se o ffmpeg falhar (cai pro arquivo original).
  def denoise(path)
    out = "#{path}.clean.ogg"
    cmd = %W[
      ffmpeg -y -hide_banner -loglevel error -i #{path}
      -af highpass=f=80,afftdn=nr=20,dynaudnorm
      -c:a libopus -b:a 48k -ac 1 #{out}
    ]
    _output, status = Open3.capture2e(*cmd)
    status.success? ? out : nil
  end

  def request_transcription(path)
    file = File.open(path, 'rb')
    params = { file: file, model: MODEL, language: LANGUAGE, response_format: 'json' }
    response = client.audio.transcribe(parameters: params)
    response.is_a?(Hash) ? response['text'].to_s : ''
  ensure
    file&.close
  end

  def client
    @client ||= OpenAI::Client.new(access_token: api_key, request_timeout: REQUEST_TIMEOUT)
  end

  def api_key
    ENV['OPENAI_WHISPER_KEY'].presence ||
      InstallationConfig.find_by(name: 'OPENAI_WHISPER_KEY')&.value ||
      InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_API_KEY')&.value
  end
end
