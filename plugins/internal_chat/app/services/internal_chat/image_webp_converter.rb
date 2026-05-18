module InternalChat
  # Converte imagens enviadas no chat (PNG/JPG/etc) pra WebP antes de
  # persistir, reduzindo tamanho de armazenamento e bandwidth.
  # Recebe um ActionDispatch::Http::UploadedFile e devolve outro com o WebP,
  # ou o original em caso de falha (resiliente — nunca bloqueia o envio).
  class ImageWebpConverter
    QUALITY = 82
    SKIP_TYPES = %w[image/webp image/gif].freeze

    def self.call(upload)
      new(upload).call
    end

    def initialize(upload)
      @upload = upload
    end

    def call
      return @upload unless image_upload?
      return @upload if SKIP_TYPES.include?(@upload.content_type)
      return @upload unless @upload.tempfile.respond_to?(:path)

      converted = convert
      return @upload unless converted

      converted
    rescue StandardError => e
      Rails.logger.warn "[InternalChat::ImageWebpConverter] failed: #{e.class}: #{e.message}"
      @upload
    end

    private

    def image_upload?
      @upload.respond_to?(:content_type) &&
        @upload.content_type.to_s.start_with?('image/')
    end

    def convert
      src = @upload.tempfile.path
      dst = "#{src}.webp"

      MiniMagick::Tool::Convert.new do |c|
        c << src
        c.quality QUALITY
        c << dst
      end
      return nil unless File.exist?(dst) && File.size(dst).positive?

      base = File.basename(@upload.original_filename, '.*')
      ActionDispatch::Http::UploadedFile.new(
        tempfile: File.open(dst, 'rb'),
        filename: "#{base}.webp",
        type: 'image/webp',
      )
    end
  end
end
