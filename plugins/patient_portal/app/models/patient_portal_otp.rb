# OTP de 6 dígitos para login passwordless do paciente.
# PRD §5.4: TTL 10 min, máximo 3 tentativas, invalidado após uso.
# `code_digest` guarda bcrypt do código — nunca o código em claro.
class PatientPortalOtp < ApplicationRecord
  OTP_TTL_MINUTES = 10
  MAX_ATTEMPTS    = 3
  # Anti-flood: em produção limitamos a 5 OTPs por identifier nas últimas 24h.
  # Em dev/test, relaxamos para 50 — pra não travar o desenvolvedor refazendo
  # o fluxo. NUNCA suba esse valor em prod sem revisar o trade-off com PRD §17.4.
  MAX_OTPS_PER_DAY = (Rails.env.production? ? 5 : 50)

  CHANNELS = %w[whatsapp email].freeze

  # Não usamos `has_secure_password` porque o nome do campo é não-padrão (code_digest).
  attr_accessor :code

  validates :identifier, presence: true
  validates :channel, inclusion: { in: CHANNELS }

  before_validation :hash_code, on: :create
  before_validation :set_expires_at, on: :create

  scope :active, -> { where(used_at: nil).where('expires_at > ?', Time.current) }

  def self.generate_code
    rand(100_000..999_999).to_s
  end

  def matches?(submitted_code)
    BCrypt::Password.new(code_digest) == submitted_code.to_s
  end

  def expired?
    expires_at <= Time.current
  end

  def consumable?
    used_at.nil? && !expired? && attempts < MAX_ATTEMPTS
  end

  def consume!
    update!(used_at: Time.current)
  end

  def register_failed_attempt!
    increment!(:attempts)
  end

  private

  def hash_code
    return if code.blank?

    self.code_digest = BCrypt::Password.create(code.to_s)
  end

  def set_expires_at
    self.expires_at ||= OTP_TTL_MINUTES.minutes.from_now
  end
end
