require 'net/http'
require 'json'

# Transcreve voice notes (anexos `file_type: :audio` em
# `Message.attachments`) em texto PT-BR via OpenAI Whisper API.
# Whisper foi escolhido sobre Gemini multimodal por:
#   1. Qualidade comprovada em PT-BR (acentos, gírias regionais).
#   2. Custo previsível ($0.006/min).
#   3. Endpoint dedicado (model `whisper-1`) — não consome quota
#      do modelo principal de chat.
#
# Tolerante: qualquer erro (sem API key, áudio inválido, timeout)
# retorna nil. Caller (ChatResponseJob) trata o nil postando uma
# mensagem padrão pro paciente "não consegui ouvir, pode digitar?".
class AiAgent::Multimodal::AudioTranscriber
  Result = Struct.new(:text, :duration_seconds, :model, keyword_init: true)

  WHISPER_ENDPOINT = 'https://api.openai.com/v1/audio/transcriptions'.freeze
  WHISPER_MODEL = 'whisper-1'.freeze
  DEFAULT_LANGUAGE = 'pt'.freeze
  MAX_AUDIO_BYTES = 25 * 1024 * 1024  # 25MB — limite da API Whisper
  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 60                    # transcrição pode levar até 1min

  # Aceita um Attachment do Chatwoot (ActiveStorage). Lê o blob,
  # POSTa multipart pro Whisper, devolve texto.
  def initialize(attachment:, language: DEFAULT_LANGUAGE)
    @attachment = attachment
    @language = language
  end

  # Resultado especial: indica que o blob ainda não chegou ao storage
  # (race condition: WhatsApp commitou o Message antes do upload do
  # blob terminar). Caller pode reenfileirar e tentar de novo.
  FILE_NOT_READY = :file_not_ready

  # Tenta abrir o blob com retry curto pra cobrir race entre
  # `Message.after_create_commit` (dispara o listener) e o término
  # do upload do attachment. Em produção esse delay costuma ser
  # 0–2s; 3 tentativas com sleep 1s cobre o caso normal sem
  # bloquear o worker por tempo significativo.
  def call
    return nil unless @attachment&.file&.attached?
    return nil if @attachment.file.byte_size > MAX_AUDIO_BYTES

    api_key = openai_api_key
    return nil if api_key.blank?

    attempts = 0
    begin
      attempts += 1
      @attachment.file.blob.open do |tempfile|
        response = post_to_whisper(tempfile, api_key)
        return nil unless response.is_a?(Net::HTTPSuccess)

        payload = JSON.parse(response.body)
        text = payload['text'].to_s.strip
        return nil if text.empty?

        return Result.new(text: text, duration_seconds: @attachment.file.blob.metadata['duration'], model: WHISPER_MODEL)
      end
    rescue ActiveStorage::FileNotFoundError => e
      # Caller (ChatResponseJob) trata FILE_NOT_READY reenfileirando
      # com delay maior, fora do worker thread.
      Rails.logger.info("[AiAgent::Multimodal::AudioTranscriber] attachment=#{@attachment.id} blob ainda não disponível (tentativa #{attempts}/3)")
      if attempts < 3
        sleep 1.0
        retry
      end

      Rails.logger.warn("[AiAgent::Multimodal::AudioTranscriber] attachment=#{@attachment.id} desistiu após 3 tentativas: #{e.class}")
      return FILE_NOT_READY
    end
  rescue StandardError => e
    Rails.logger.warn("[AiAgent::Multimodal::AudioTranscriber] attachment=#{@attachment&.id} #{e.class}: #{e.message[0, 200]}")
    nil
  end

  private

  def openai_api_key
    ::RubyLLM.config.openai_api_key.presence ||
      InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_API_KEY')&.value.presence ||
      ENV.fetch('OPENAI_API_KEY', nil)
  end

  def post_to_whisper(tempfile, api_key)
    uri = URI(WHISPER_ENDPOINT)

    boundary = "----RubyMultipartBoundary#{SecureRandom.hex(16)}"
    body = build_multipart_body(tempfile, boundary)

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = OPEN_TIMEOUT
    http.read_timeout = READ_TIMEOUT

    req = Net::HTTP::Post.new(uri)
    req['Authorization'] = "Bearer #{api_key}"
    req['Content-Type'] = "multipart/form-data; boundary=#{boundary}"
    req.body = body

    http.request(req)
  end

  def build_multipart_body(tempfile, boundary)
    filename = original_filename
    mime = @attachment.file.content_type.presence || 'audio/ogg'

    parts = []
    parts << "--#{boundary}\r\n"
    parts << %(Content-Disposition: form-data; name="file"; filename="#{filename}"\r\n)
    parts << "Content-Type: #{mime}\r\n\r\n"
    parts << File.binread(tempfile.path)
    parts << "\r\n"
    parts << "--#{boundary}\r\n"
    parts << %(Content-Disposition: form-data; name="model"\r\n\r\n)
    parts << WHISPER_MODEL
    parts << "\r\n"
    parts << "--#{boundary}\r\n"
    parts << %(Content-Disposition: form-data; name="language"\r\n\r\n)
    parts << @language
    parts << "\r\n"
    parts << "--#{boundary}\r\n"
    # `response_format=json` é o default mas explicitar evita
    # surpresas se OpenAI mudar default no futuro.
    parts << %(Content-Disposition: form-data; name="response_format"\r\n\r\n)
    parts << 'json'
    parts << "\r\n"
    parts << "--#{boundary}--\r\n"
    parts.join.force_encoding(Encoding::ASCII_8BIT)
  end

  def original_filename
    meta = @attachment.file.blob.metadata
    meta['filename'].presence || @attachment.file.filename.to_s.presence || 'audio.ogg'
  end
end
