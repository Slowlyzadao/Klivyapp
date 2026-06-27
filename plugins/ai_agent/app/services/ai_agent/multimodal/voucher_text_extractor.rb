require 'fileutils'

# MVP lançamento por voucher: lê a FOTO de um voucher/cupom de desconto que a
# aluna enviou no WhatsApp e extrai o texto (desconto + procedimento) via
# Gemini multimodal (RubyLLM). Espelha o padrão de blob+retry do
# AudioTranscriber (race entre Message.after_create_commit e o upload do blob).
#
# Tolerante: qualquer erro retorna nil; blob ainda não disponível retorna
# FILE_NOT_READY (caller reenfileira). Imagem sem voucher legível → o texto
# vem como SEM_VOUCHER (o caller decide o que fazer).
class AiAgent::Multimodal::VoucherTextExtractor
  Result = Struct.new(:text, :has_voucher, :model, keyword_init: true)

  FILE_NOT_READY = :file_not_ready
  MAX_IMAGE_BYTES = 15 * 1024 * 1024
  NO_VOUCHER_SENTINEL = 'SEM_VOUCHER'.freeze

  PROMPT = <<~PT.strip.freeze
    Você está lendo a FOTO de um voucher/cupom de desconto de uma clínica de
    estética. Extraia, em no máximo 2 linhas, o que está escrito que importa:
    o DESCONTO/benefício e o PROCEDIMENTO (ex.: "30% de desconto em
    Preenchimento Labial"). Responda apenas com esse texto, sem comentar.
    Se a imagem NÃO for um voucher/cupom legível (sem desconto/benefício
    visível), responda exatamente: #{NO_VOUCHER_SENTINEL}
  PT

  def initialize(attachment:)
    @attachment = attachment
  end

  def call
    return nil unless @attachment&.file&.attached?
    return nil if @attachment.file.byte_size > MAX_IMAGE_BYTES

    wire_gemini_credentials!
    open_and_extract
  rescue StandardError => e
    Rails.logger.warn("[AiAgent::Multimodal::VoucherTextExtractor] attachment=#{@attachment&.id} #{e.class}: #{e.message[0, 200]}")
    nil
  end

  private

  # Abre o blob com retry curto (mesmo motivo do AudioTranscriber).
  def open_and_extract
    attempts = 0
    begin
      attempts += 1
      @attachment.file.blob.open { |tempfile| extract_from(tempfile) }
    rescue ActiveStorage::FileNotFoundError => e
      if attempts < 3
        sleep 1.0
        retry
      end
      Rails.logger.warn("[AiAgent::Multimodal::VoucherTextExtractor] attachment=#{@attachment.id} blob indisponível: #{e.class}")
      FILE_NOT_READY
    end
  end

  # RubyLLM detecta o mime pela EXTENSÃO do path; o tempfile do ActiveStorage
  # não tem extensão → copia pra um path com a extensão certa antes de mandar.
  def extract_from(tempfile)
    path = "#{tempfile.path}#{extension}"
    FileUtils.cp(tempfile.path, path)
    raw = ask_gemini(path)
    return nil if raw.blank?

    has = raw.upcase.exclude?(NO_VOUCHER_SENTINEL)
    Result.new(text: raw, has_voucher: has, model: model_name)
  ensure
    FileUtils.rm_f(path) if path
  end

  def ask_gemini(path)
    chat = RubyLLM.chat(model: model_name, provider: :gemini, assume_model_exists: true)
    # Desliga o "thinking" do Gemini 3.x (latência) — igual ao ChatService.
    chat.with_params(generationConfig: { thinkingConfig: { thinkingBudget: 0 } })
    chat.ask(PROMPT, with: path).content.to_s.strip
  end

  def model_name
    InstallationConfig.find_by(name: 'CAPTAIN_GEMINI_MODEL')&.value.presence || 'gemini-3-flash-preview'
  end

  def extension
    case @attachment.file.content_type.to_s
    when 'image/png' then '.png'
    when 'image/webp' then '.webp'
    when 'image/heic', 'image/heif' then '.heic'
    else '.jpg'
    end
  end

  def wire_gemini_credentials!
    key = InstallationConfig.find_by(name: 'CAPTAIN_GEMINI_API_KEY')&.value
    RubyLLM.config.gemini_api_key = key if key.present?
  end
end
