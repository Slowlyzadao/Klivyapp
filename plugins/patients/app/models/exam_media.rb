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

  ALLOWED_CONTENT_TYPES = %w[
    image/jpeg image/png image/gif image/webp image/heic image/heif
    application/pdf
    video/mp4 video/quicktime video/x-msvideo video/webm
    application/dicom image/dicom
    application/octet-stream
  ].freeze

  validates :patient_id, presence: true
  validates :account_id, presence: true
  validates :category, presence: true, inclusion: { in: CATEGORIES }
  validate :file_must_be_attached, on: :create
  validate :file_content_type_and_size, if: :file_attached?

  # Callbacks
  before_create :capture_file_metadata
  after_create_commit :record_timeline_exam_uploaded

  # Scopes úteis
  scope :by_category, ->(cat) { where(category: cat) }
  scope :before_afters, -> { where(category: 'antes_depois') }
  scope :photos, -> { where(category: 'foto_clinica') }
  scope :xrays, -> { where(category: 'rx') }
  scope :with_session, ->(id) { where(session_log_id: id) }

  def soft_delete!
    update!(deleted_at: Time.current)
  end

  def deleted?
    deleted_at.present?
  end

  # Retorna URL assinada com expiração de 15 minutos (NUNCA URL pública)
  def signed_url(expires_in: 15.minutes, disposition: :inline)
    return nil unless file.attached?

    Rails.application.routes.url_helpers.rails_blob_url(
      file,
      expires_in: expires_in,
      disposition: disposition,
      host: Rails.application.config.action_mailer.default_url_options&.dig(:host) || 'localhost:3000'
    )
  rescue StandardError
    nil
  end

  def image?
    %w[foto_clinica antes_depois intraoral rx tomografia laudo].include?(category)
  end

  def video?
    category == 'video'
  end

  def pdf?
    category == 'laudo' && mime_type&.include?('pdf')
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

    errors.add(:file, :invalid, message: 'formato de arquivo não suportado') unless ALLOWED_CONTENT_TYPES.include?(file.content_type)
    return unless file.byte_size > 500.megabytes

    errors.add(:file, :too_large, message: 'arquivo muito grande (máximo 500MB)')
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
