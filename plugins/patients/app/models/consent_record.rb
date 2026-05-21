class ConsentRecord < ApplicationRecord
  include TimelineTrackable
  include BeclinicPurgeableAttachment

  # Soft delete
  scope :active, -> { where(deleted_at: nil) }
  scope :deleted, -> { where.not(deleted_at: nil) }

  # Associations
  belongs_to :patient
  belongs_to :account
  belongs_to :form_template, optional: true
  belongs_to :created_by, class_name: 'User', optional: true

  has_one_attached :signature_image
  purges_attachment_with job_class: Patients::ConsentRecordPurgeJob


  # Status enum
  #
  # Status canônico: `pendente / signed / vencido / revogado`.
  # Diferenciação do canal de assinatura vive na coluna `mode`
  # (`local_tablet` / `remote_link`), exposta no JSON via `signature_method`
  # ('local'/'remote').
  #
  # Backfill `assinado_localmente`/`assinado_remotamente` → `signed` rodado
  # em 2026-05-04 via `db/migrate/20260503190100_backfill_consent_signed_status.rb`
  # (count legacy verificado = 0). Constante `LEGACY_SIGNED_STATUSES` removida.
  SIGNED_STATUSES = %w[signed].freeze
  STATUSES = (%w[pendente] + SIGNED_STATUSES + %w[vencido revogado]).freeze
  MODES    = %w[local_tablet remote_link].freeze

  validates :patient_id, presence: true
  validates :account_id, presence: true
  validates :title, presence: true, length: { minimum: 2, maximum: 255 }
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :mode, inclusion: { in: MODES }, allow_blank: true
  # Explicit length for text columns to override ApplicationRecord's generic 20k limit.
  # signature_blob holds base64-encoded PNG images which can easily be 200k+ chars.
  validates :signature_blob, length: { maximum: 500_000 }, allow_blank: true
  validates :body, length: { maximum: 100_000 }, allow_blank: true
  validates :observations, length: { maximum: 50_000 }, allow_blank: true

  before_save   :calculate_expires_at
  # Callbacks
  before_create :generate_remote_token
  after_create_commit :record_timeline_consent_created
  after_update_commit :record_timeline_consent_signed, if: :saved_change_to_status?

  # Scopes
  scope :pending, -> { where(status: 'pendente') }
  scope :signed, -> { where(status: SIGNED_STATUSES) }
  scope :expired, -> { where(status: 'vencido') }
  scope :pending_or_expired, -> { where(status: %w[pendente vencido]) }
  scope :today_pending, lambda {
    where(status: 'pendente')
      .where('consent_records.created_at >= ?', Date.today.beginning_of_day)
  }

  def soft_delete!
    update!(deleted_at: Time.current)
    schedule_attachment_purge!
  end

  def deleted?
    deleted_at.present?
  end

  def pending?
    status == 'pendente'
  end

  def signed?
    SIGNED_STATUSES.include?(status)
  end

  # 'local' ou 'remote' — derivado de `mode`. Padrão Klivy preferido sobre
  # checar `assinado_localmente`/`assinado_remotamente` no status.
  def signature_method
    case mode
    when 'local_tablet' then 'local'
    when 'remote_link'  then 'remote'
    end
  end

  def expired?
    status == 'vencido' || (expires_at.present? && expires_at < Time.current)
  end

  def revoked?
    status == 'revogado'
  end

  def sign_locally!(signature_blob:, ip_address:, device_info: nil)
    raise StandardError, 'Consentimento já foi assinado' if signed?
    raise StandardError, 'Consentimento está vencido' if expired?

    signed_at_time = Time.current

    update!(
      status: 'signed',
      mode: 'local_tablet',
      signature_blob: signature_blob,
      ip_address: ip_address,
      device_info: device_info,
      signed_at: signed_at_time,
      integrity_hash: generate_integrity_hash(signature_blob, signed_at_time)
    )
  end

  def sign_remotely!(signature_blob:, ip_address:, device_info: nil)
    raise StandardError, 'Consentimento já foi assinado' if signed?
    raise StandardError, 'Consentimento está vencido' if expired?
    raise StandardError, 'Token expirado' if remote_link_expires_at.present? && remote_link_expires_at < Time.current

    signed_at_time = Time.current

    update!(
      status: 'signed',
      mode: 'remote_link',
      signature_blob: signature_blob,
      ip_address: ip_address,
      device_info: device_info,
      signed_at: signed_at_time,
      integrity_hash: generate_integrity_hash(signature_blob, signed_at_time),
      remote_token: nil  # Invalida o token após uso
    )
  end

  def revoke!
    raise StandardError, 'Consentimento já está revogado' if revoked?

    update!(status: 'revogado')
  end

  def send_remote_link!
    update!(
      remote_link_sent_at: Time.current,
      remote_link_expires_at: 48.hours.from_now
    )
  end

  # Verifica a integridade do hash armazenado
  def integrity_valid?
    return false if signature_blob.blank? || signed_at.blank? || integrity_hash.blank?

    expected = generate_integrity_hash(signature_blob, signed_at)
    expected == integrity_hash
  end

  # Roadmap #17.1 ✅ — proxy via SecureBlobsController com cross-tenant guard.
  # Token signed (15min) → controller valida current_user pertence à account →
  # redirect para URL real com janela curta (30s). Frontend continua usando
  # `<img :src>` direto, sem mudança no consumo.
  def signature_image_url
    return nil unless signature_image.attached?

    token = Patients::SecureBlobTokenService.encode(
      blob_id: signature_image.blob.id,
      account_id: account_id,
      expires_in: 15.minutes
    )
    Rails.application.routes.url_helpers.secure_blob_url(token: token)
  rescue StandardError
    nil
  end

  # Recalcula status vencido em tempo real para qualquer variante assinada.
  def computed_status
    return 'vencido' if expires_at.present? && expires_at < Time.current && signed?

    status
  end

  private

  def generate_integrity_hash(blob, timestamp)
    Digest::SHA256.hexdigest("#{patient_id}#{id}#{blob}#{timestamp}")
  end

  def generate_remote_token
    self.remote_token = SecureRandom.hex(32) if remote_token.blank?
  end

  def calculate_expires_at
    return unless signed_at.present? && expires_after_days.present?

    self.expires_at = signed_at + expires_after_days.days
  end

  def record_timeline_consent_created
    record_timeline_event!(
      event_type: 'consent_signed',
      label: "Consentimento criado: #{title}",
      actor: created_by,
      occurred_at: Time.current,
      metadata: { titulo: title.to_s, status: status.to_s, modo: mode.to_s }
    )
  end

  def record_timeline_consent_signed
    return unless signed?

    record_timeline_event!(
      event_type: 'consent_signed',
      label: "Consentimento assinado: #{title}",
      actor: created_by,
      occurred_at: Time.current,
      metadata: { titulo: title.to_s, modo: mode.to_s, ip: ip_address.to_s }
    )
  end
end
