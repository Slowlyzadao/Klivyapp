class ConsentRecord < ApplicationRecord
  include TimelineTrackable

  # Soft delete
  scope :active, -> { where(deleted_at: nil) }
  scope :deleted, -> { where.not(deleted_at: nil) }

  # Associations
  belongs_to :patient
  belongs_to :account
  belongs_to :form_template, optional: true
  belongs_to :created_by, class_name: 'User', optional: true

  has_one_attached :signature_image


  # Status enum
  STATUSES = %w[pendente assinado_localmente assinado_remotamente vencido revogado].freeze
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
  after_commit  :update_patient_recall_flag, on: [:create, :update]
  after_create_commit :record_timeline_consent_created
  after_update_commit :record_timeline_consent_signed, if: :saved_change_to_status?

  # Scopes
  scope :pending, -> { where(status: 'pendente') }
  scope :signed, -> { where(status: %w[assinado_localmente assinado_remotamente]) }
  scope :expired, -> { where(status: 'vencido') }
  scope :pending_or_expired, -> { where(status: %w[pendente vencido]) }
  scope :today_pending, lambda {
    where(status: 'pendente')
      .where('consent_records.created_at >= ?', Date.today.beginning_of_day)
  }

  def soft_delete!
    update!(deleted_at: Time.current)
  end

  def deleted?
    deleted_at.present?
  end

  def pending?
    status == 'pendente'
  end

  def signed?
    %w[assinado_localmente assinado_remotamente].include?(status)
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
      status: 'assinado_localmente',
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
      status: 'assinado_remotamente',
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

  def signature_image_url
    return nil unless signature_image.attached?

    Rails.application.routes.url_helpers.rails_blob_url(
      signature_image,
      host: ENV.fetch('FRONTEND_URL', 'http://localhost:3000'),
      expires_in: 2.hours,
      disposition: :inline
    )
  end

  # Recalcula status vencido em tempo real
  def computed_status
    return 'vencido' if expires_at.present? && expires_at < Time.current && status == 'assinado_localmente'
    return 'vencido' if expires_at.present? && expires_at < Time.current && status == 'assinado_remotamente'

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

  def update_patient_recall_flag
    true
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
    return unless status.in?(%w[assinado_localmente assinado_remotamente])

    record_timeline_event!(
      event_type: 'consent_signed',
      label: "Consentimento assinado: #{title}",
      actor: created_by,
      occurred_at: Time.current,
      metadata: { titulo: title.to_s, modo: mode.to_s, ip: ip_address.to_s }
    )
  end
end
