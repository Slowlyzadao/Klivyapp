class ExamMedia < ApplicationRecord
  include TimelineTrackable

  self.table_name = 'exam_medias'

  # Active Storage — o arquivo real vai para S3/GCS, aqui ficam apenas metadados
  has_one_attached :file

  # Soft delete
  scope :active, -> { where(deleted_at: nil) }
  scope :deleted, -> { where.not(deleted_at: nil) }

  # Associations
  belongs_to :patient
  belongs_to :account
  belongs_to :uploaded_by, class_name: 'User', optional: true
  belongs_to :session_log, optional: true
  belongs_to :agenda_event, foreign_key: :appointment_id, optional: true
  belongs_to :exam_folder, optional: true

  # Enums — categorias de exames e imagens
  CATEGORIES = %w[
    rx
    tomografia
    foto_clinica
    antes_depois
    intraoral
    laudo
    laboratorial
    video
    outro
  ].freeze

  IMAGE_TYPES = %w[image/jpeg image/png image/gif image/webp image/heic image/heif].freeze
  PDF_TYPES   = %w[application/pdf].freeze
  VIDEO_TYPES = %w[video/mp4 video/quicktime video/webm].freeze
  ALLOWED_CONTENT_TYPES = (IMAGE_TYPES + PDF_TYPES + VIDEO_TYPES).freeze

  # Limites por tipo (alinhado com requisito do produto)
  SIZE_LIMITS = {
    image: 5.megabytes,
    pdf:   10.megabytes,
    video: 20.megabytes
  }.freeze

  validates :patient_id, presence: true
  validates :account_id, presence: true
  validates :category, presence: true, inclusion: { in: CATEGORIES }
  validate :file_must_be_attached, on: :create
  validate :file_content_type_and_size, if: :file_attached?

  # Callbacks
  before_validation :derive_category_from_file, on: :create
  before_create :capture_file_metadata
  after_create_commit :record_timeline_exam_uploaded

  # Scopes úteis
  scope :by_category, ->(cat) { where(category: cat) }
  scope :before_afters, -> { where(category: 'antes_depois') }
  scope :photos, -> { where(category: 'foto_clinica') }
  scope :xrays, -> { where(category: 'rx') }
  scope :with_session, ->(id) { where(session_log_id: id) }

  # Janela de retenção antes do purge físico (blob + record).
  # Usuário pode restaurar manualmente nesse intervalo (admin tools).
  PURGE_AFTER = 30.days

  def soft_delete!
    update!(deleted_at: Time.current)
    ::Patients::ExamMediaPurgeJob.set(wait: PURGE_AFTER).perform_later(id)
  end

  def deleted?
    deleted_at.present?
  end

  # Retorna URL assinada com expiração de 1 hora (NUNCA URL pública)
  # Host vem de config.active_storage.default_url_options — não usar fallback localhost.
  def signed_url(expires_in: 1.hour, disposition: :inline)
    return nil unless file.attached?

    Rails.application.routes.url_helpers.rails_blob_url(
      file,
      expires_in: expires_in,
      disposition: disposition
    )
  rescue StandardError
    nil
  end

  # Thumbnail otimizado para a galeria (somente para imagens).
  # Para vídeo/PDF retorna nil e o frontend usa o ícone genérico.
  # Variants são geradas sob demanda e cacheadas pelo ActiveStorage (1ª request lenta, demais rápidas).
  # NOTE: ActiveStorage só aceita métodos da whitelist `supported_image_processing_methods`;
  # `saver: { quality: ... }` não está nela — para baixar peso da imagem o caminho seria via
  # processor custom ou um `format: :webp` (também whitelisted). 400px já dá compressão suficiente.
  def thumbnail_url(expires_in: 1.hour)
    return nil unless file.attached?
    return nil unless file_kind == :image
    return nil unless file.variable?

    variant = file.variant(resize_to_limit: [400, 400])
    Rails.application.routes.url_helpers.rails_representation_url(
      variant,
      expires_in: expires_in,
      disposition: :inline
    )
  rescue StandardError
    nil
  end

  # Classifica o arquivo pelo content_type real do blob (não pela categoria informada)
  def file_kind
    return :unknown unless file.attached?

    ct = file.content_type.to_s
    return :image if IMAGE_TYPES.include?(ct)
    return :pdf   if PDF_TYPES.include?(ct)
    return :video if VIDEO_TYPES.include?(ct)

    :unknown
  end

  def image?
    file_kind == :image || %w[foto_clinica antes_depois intraoral rx tomografia].include?(category)
  end

  def video?
    file_kind == :video || category == 'video'
  end

  def pdf?
    file_kind == :pdf || mime_type&.include?('pdf')
  end

  private

  def capture_file_metadata
    return unless file.attached?

    self.file_name ||= sanitize_filename(file.filename.to_s)
    self.mime_type ||= file.content_type
    self.file_size ||= file.byte_size
  end

  # Sanitiza nome de arquivo preservando extensão e legibilidade em PT-BR.
  # Ex: "Exame da Maria (2024) .pdf" → "exame-da-maria-2024.pdf"
  def sanitize_filename(raw)
    return 'arquivo' if raw.blank?

    ext = File.extname(raw).downcase
    base = File.basename(raw, ext)
    slug = I18n.transliterate(base)
               .downcase
               .gsub(/[^\w\s-]/, '')
               .strip
               .gsub(/\s+/, '-')
               .gsub(/-+/, '-')
               .delete_prefix('-')
               .delete_suffix('-')
    slug = 'arquivo' if slug.blank?
    slug = slug[0, 100] # limite defensivo contra nomes muito longos
    "#{slug}#{ext}"
  end

  def file_attached?
    file.attached?
  end

  def file_must_be_attached
    errors.add(:file, :blank, message: 'deve ser anexado') unless file.attached?
  end

  def file_content_type_and_size
    return unless file.attached?

    unless ALLOWED_CONTENT_TYPES.include?(file.content_type)
      errors.add(:file, "formato não suportado (#{file.content_type}). Aceitos: imagem (JPG/PNG/WEBP/HEIC), PDF, vídeo (MP4/MOV/WEBM)")
      return
    end

    kind  = file_kind
    limit = SIZE_LIMITS[kind]
    return unless limit && file.byte_size > limit

    human_limit = ActiveSupport::NumberHelper.number_to_human_size(limit)
    errors.add(:file, "arquivo muito grande para #{kind} (máximo #{human_limit})")
  end

  # Define automaticamente a categoria a partir do tipo real do arquivo,
  # evitando confiar em string vinda do client (HEIC do iPhone vinha como 'outro').
  def derive_category_from_file
    return unless file.attached?
    return if category.present? && category != 'outro'

    self.category = case file_kind
                    when :video then 'video'
                    when :pdf   then 'laudo'
                    when :image then 'foto_clinica'
                    else             'outro'
                    end
  end

  def record_timeline_exam_uploaded
    record_timeline_event!(
      event_type: 'exam_uploaded',
      label: "Exame/imagem enviado: #{file_name || category}",
      actor: uploaded_by,
      occurred_at: Time.current,
      metadata: { categoria: category.to_s, arquivo: file_name.to_s }
    )
  end
end
