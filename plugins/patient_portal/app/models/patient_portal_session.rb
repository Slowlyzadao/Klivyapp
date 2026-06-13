# Sessão JWT do paciente no portal.
# PRD §5.2: TTL 7 dias (30 dias se "lembrar dispositivo").
# `jwt_jti` (JWT ID) é único — permite revogar uma sessão específica sem invalidar todas.
#
# Sprint I — Sessão tem agora dois patients:
#   - `patient_id`         : quem LOGOU (acting/responsible)
#   - `active_patient_id`  : quem está sendo ACESSADO no momento (self ou dependente)
# Para sessões single-patient, ambos apontam pro mesmo id.
class PatientPortalSession < ApplicationRecord
  DEFAULT_TTL_DAYS    = 7
  REMEMBERED_TTL_DAYS = 30

  belongs_to :account
  belongs_to :patient
  belongs_to :active_patient, class_name: 'Patient', foreign_key: :active_patient_id

  validates :jwt_jti, presence: true, uniqueness: true

  scope :active, -> { where(revoked_at: nil).where('expires_at > ?', Time.current) }

  def revoked?
    revoked_at.present?
  end

  def expired?
    expires_at <= Time.current
  end

  def valid_session?
    !revoked? && !expired?
  end

  def touch_last_seen!(ip: nil, user_agent: nil)
    update!(last_seen_at: Time.current, ip: ip || self.ip, user_agent: user_agent || self.user_agent)
  end

  def acting_on_dependent?
    active_patient_id != patient_id
  end
end
