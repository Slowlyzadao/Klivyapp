# Consent do paciente para gravação da teleconsulta.
#
# Antes da extração do plugin telemed, esses consents viviam em
# PatientPortalConsent com term_type='telemedicine_recording'. Migrados pra
# tabela própria pra isolar o plugin.
#
# Idempotência: único por (account, patient, term_version). Re-emissão do
# termo (novo term_version) cria row nova; revogação não deleta — só seta
# `revoked_at`.
class TelemedConsent < ApplicationRecord
  CURRENT_TERM_VERSION = '1.0'.freeze

  belongs_to :account
  belongs_to :patient

  validates :term_version, presence: true
  validates :accepted_at,  presence: true

  scope :active, -> { where(revoked_at: nil) }

  def self.accept!(account:, patient:, ip: nil, user_agent: nil)
    find_or_create_by!(
      account:      account,
      patient:      patient,
      term_version: CURRENT_TERM_VERSION
    ) do |consent|
      consent.accepted_at = Time.current
      consent.ip          = ip
      consent.user_agent  = user_agent.to_s.first(255)
    end
  end
end
