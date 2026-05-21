# Convite emitido pela clínica para o paciente acessar o portal.
# PRD §5.6. Auto-expira em INVITE_TTL_DAYS dias.
class PortalInvite < ApplicationRecord
  INVITE_TTL_DAYS = 30
  CHANNELS = %w[whatsapp email].freeze

  belongs_to :account
  belongs_to :patient
  belongs_to :invited_by, class_name: 'User', foreign_key: 'invited_by_user_id', optional: true

  validates :token, presence: true, uniqueness: true
  validates :channel, inclusion: { in: CHANNELS }

  before_validation :set_defaults, on: :create

  scope :pending,  -> { where(accepted_at: nil).where('expires_at > ?', Time.current) }
  scope :accepted, -> { where.not(accepted_at: nil) }

  def expired?
    expires_at <= Time.current
  end

  def accept!
    update!(accepted_at: Time.current)
  end

  private

  def set_defaults
    self.token       ||= SecureRandom.urlsafe_base64(32)
    self.expires_at  ||= INVITE_TTL_DAYS.days.from_now
  end
end
