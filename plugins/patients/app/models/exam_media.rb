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

  # Roadmap #17.1 ✅ — proxy via SecureBlobsController com cross-tenant guard.
  # Token signed (1h, mantida por UX da galeria de fotos) → controller valida
  # current_user pertence à account → redirect com janela curta (30s).
  # `disposition` é ignorado — o controller decide ao redirecionar.
  def signed_url(expires_in: 1.hour, disposition: :inline)
    return nil unless file.attached?

    token = Patients::SecureBlobTokenService.encode(
      blob_id: file.blob.id,
      account_id: account_id,
      expires_in: expires_in
    )
    Rails.application.routes.url_helpers.secure_blob_url(token: token)
  rescue StandardError
    nil
  end

  # Thumbnail otimizado para a galeria (somente para imagens).
  # Para vídeo/PDF retorna nil e o frontend usa o ícone genérico.
  # Variants são geradas sob demanda e cacheadas pelo ActiveStorage (1ª request lenta, demais rápidas).
  # NOTE: ActiveStorage só aceita métodos da whitelist `supported_image_processing_methods`;
  # `saver: { quality: ... }` não está nela — para baixar peso da imagem o caminho seria via
  # processor custom ou um `format: :webp` (também whitelisted). 400px já dá compressão suficiente.
  # Roadmap #17.1 ✅ — variant do thumbnail também passa pelo guard.
  # Controller decodifica `transformations` do token e regenera o variant
  # antes de redirecionar.
  def thumbnail_url(expires_in: 1.hour)
    return nil unless file.attached?
    return nil unless file_kind == :image
    return nil unless file.variable?

    token = Patients::SecureBlobTokenService.encode(
      blob_id: file.blob.id,
      account_id: account_id,
      expires_in: expires_in,
      transformations: { resize_to_limit: [400, 400] }
    )
    Rails.application.routes.url_helpers.secure_blob_url(token: token)
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

  # Sanitiza nome de arquivo PRESERVANDO acentos e caracteres legíveis em
  # PT-BR. Remove apenas o que é perigoso pra path traversal ou injeção em
  # shell/URL: `/`, `\`, `..`, controle (`\x00-\x1f`), e símbolos que quebram
  # filesystems (`<>:"|?*`).
  #
  # Ex: "José_foto (2024).pdf" → "José_foto (2024).pdf" (preservado)
  # Ex: "../../../etc/passwd" → "etc-passwd" (sanitizado)
  # Ex: "Exame:resultado<x>.pdf" → "Exame-resultado-x-.pdf"
  def sanitize_filename(raw)
    return 'arquivo' if raw.blank?

    ext = File.extname(raw).downcase
    base = File.basename(raw, ext)

    # 1. Remove path traversal e separadores de diretório
    base = base.gsub(%r{[/\\]}, '-')
    base = base.gsub(/\.{2,}/, '-') # dois ou mais pontos seguidos viram '-'

    # 2. Remove caracteres de controle e símbolos perigosos pra filesystem
    base = base.gsub(/[\x00-\x1f\x7f<>:"|?*]/, '-')

    # 3. Colapsa hífens duplicados e trim
    base = base.gsub(/-+/, '-').strip.delete_prefix('-').delete_suffix('-')

    # 4. Limite de tamanho defensivo
    base = base[0, 100]
    base = 'arquivo' if base.blank?
    "#{base}#{ext}"
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
